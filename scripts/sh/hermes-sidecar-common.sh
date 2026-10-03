#!/usr/bin/env bash

# Shared host state and authentication for the optional Hermes MCP sidecars.

dotfiles_hermes_data_dir() {
  if [[ -n ${HERMES_DATA_DIR:-} ]]; then
    printf '%s\n' "$HERMES_DATA_DIR"
  elif [[ -n ${USERPROFILE:-} ]]; then
    printf '%s\n' "$USERPROFILE/.hermes"
  else
    printf '%s\n' "$HOME/.hermes"
  fi
}

dotfiles_hermes_browser_data_dir() {
  if [[ -n ${HERMES_BROWSER_DATA_DIR:-} ]]; then
    printf '%s\n' "$HERMES_BROWSER_DATA_DIR"
  else
    printf '%s\n' "$(dotfiles_hermes_data_dir)/.browser"
  fi
}

dotfiles_hermes_prepare_runtime_home() {
  local data_dir browser_data_dir mode op_env_path
  data_dir="$(dotfiles_hermes_data_dir)"
  browser_data_dir="$(dotfiles_hermes_browser_data_dir)"
  op_env_path="$data_dir/.op.env"

  mkdir -p "$data_dir" "$data_dir/.xurl" "$browser_data_dir"
  if [[ -L $op_env_path ]]; then
    dotfiles_die "Hermes service-account environment file must not be a symlink."
  fi
  if [[ -e $op_env_path && ! -f $op_env_path ]]; then
    dotfiles_die "Hermes service-account environment file must be regular."
  fi
  if [[ ! -e $op_env_path ]]; then
    (umask 077 && : >"$op_env_path") ||
      dotfiles_die "Could not create Hermes service-account environment file."
    chmod 600 "$op_env_path" ||
      dotfiles_die "Could not protect Hermes service-account environment file."
  else
    mode="$(stat -c '%a' "$op_env_path" 2>/dev/null || stat -f '%Lp' "$op_env_path")" ||
      dotfiles_die "Could not inspect Hermes service-account environment file permissions."
    [[ $mode == 600 ]] ||
      dotfiles_die "Hermes service-account environment file must have mode 0600."
  fi
}

dotfiles_hermes_service_account_ref() {
  printf '%s\n' "${DOTFILES_HERMES_OP_SERVICE_ACCOUNT_TOKEN_REF:-op://openclaw/3bgd5qtytxuvuauauyqr2p4iki/credential}"
}

dotfiles_hermes_service_account_account() {
  printf '%s\n' "${DOTFILES_HERMES_OP_SERVICE_ACCOUNT_ACCOUNT:-my.1password.com}"
}

dotfiles_hermes_service_account_read_timeout_seconds() {
  local timeout_seconds

  timeout_seconds="${DOTFILES_HERMES_OP_READ_TIMEOUT_SECONDS:-20}"
  [[ $timeout_seconds =~ ^([1-9]|[1-9][0-9]|[12][0-9]{2}|300)$ ]] || timeout_seconds=20
  printf '%s\n' "$timeout_seconds"
}

dotfiles_hermes_read_service_account_token() {
  local op_command="$1" account="$2" reference="$3" result_variable="$4"
  local data_dir temporary pid timeout_seconds elapsed_seconds=0 poll read_token status=1 timed_out=0

  data_dir="$(dotfiles_hermes_data_dir)"
  timeout_seconds="$(dotfiles_hermes_service_account_read_timeout_seconds)"
  temporary="$(mktemp "$data_dir/.op.read.XXXXXX")" || return 1
  chmod 600 "$temporary" || {
    rm -f -- "$temporary"
    return 1
  }

  "$op_command" --account "$account" read "$reference" >"$temporary" 2>/dev/null &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    for ((poll = 0; poll < 10; poll++)); do
      sleep 0.1
      kill -0 "$pid" 2>/dev/null || break
    done
    if kill -0 "$pid" 2>/dev/null; then
      ((elapsed_seconds += 1))
      if ((elapsed_seconds >= timeout_seconds)); then
        timed_out=1
        kill -TERM "$pid" 2>/dev/null || true
        kill -KILL "$pid" 2>/dev/null || true
        break
      fi
    fi
  done
  if ((timed_out != 0)); then
    wait "$pid" 2>/dev/null || true
  elif wait "$pid" 2>/dev/null; then
    read_token="$(<"$temporary")"
    printf -v "$result_variable" '%s' "$read_token"
    status=0
  fi
  rm -f -- "$temporary"
  unset read_token temporary
  return "$status"
}

dotfiles_hermes_validate_service_account_environment_cache() {
  local op_env_path="$1" mode cache_line cache_line_count cache_token

  [[ ! -L $op_env_path && -f $op_env_path ]] || return 1
  mode="$(stat -c '%a' "$op_env_path" 2>/dev/null || stat -f '%Lp' "$op_env_path")" || return 1
  [[ $mode == 600 ]] || return 1
  cache_line_count="$(awk 'END { print NR }' "$op_env_path")" || return 1
  [[ $cache_line_count == 1 ]] || return 1
  IFS= read -r cache_line <"$op_env_path" || [[ -n $cache_line ]] || return 1
  [[ $cache_line == OP_SERVICE_ACCOUNT_TOKEN=* ]] || return 1
  cache_token="${cache_line#OP_SERVICE_ACCOUNT_TOKEN=}"
  [[ -n $cache_token && $cache_token != *$'\r'* && $cache_token != *$'\n'* ]]
}

dotfiles_hermes_run_with_service_account_cache() {
  local data_dir op_env_path cache_line token status=0 xtrace_enabled=0

  data_dir="$(dotfiles_hermes_data_dir)"
  op_env_path="$data_dir/.op.env"
  if [[ $- == *x* ]]; then
    xtrace_enabled=1
    set +x
  fi
  if dotfiles_hermes_validate_service_account_environment_cache "$op_env_path" &&
    { IFS= read -r cache_line <"$op_env_path" || [[ -n $cache_line ]]; }; then
    token="${cache_line#OP_SERVICE_ACCOUNT_TOKEN=}"
    OP_SERVICE_ACCOUNT_TOKEN="$token" "$@" || status=$?
  else
    status=1
  fi
  unset token cache_line data_dir op_env_path
  if ((xtrace_enabled)); then
    set -x
  fi
  return "$status"
}

dotfiles_hermes_prepare_service_account_environment() {
  local data_dir op_env_path temporary op_command account reference token status=0 xtrace_enabled=0

  data_dir="$(dotfiles_hermes_data_dir)"
  op_env_path="$data_dir/.op.env"
  op_command="$(dotfiles_hermes_op_command)" || return 1
  account="$(dotfiles_hermes_service_account_account)"
  reference="$(dotfiles_hermes_service_account_ref)"

  if [[ $- == *x* ]]; then
    xtrace_enabled=1
    set +x
  fi
  if [[ ${DOTFILES_HERMES_REFRESH_SERVICE_ACCOUNT:-0} != 1 ]] &&
    dotfiles_hermes_validate_service_account_environment_cache "$op_env_path"; then
    :
  elif dotfiles_hermes_read_service_account_token "$op_command" "$account" "$reference" token &&
    [[ -n $token && $token != *$'\n'* && $token != *$'\r'* ]]; then
    temporary="$(mktemp "$data_dir/.op.env.XXXXXX")" || status=1
    if ((status == 0)); then
      if (umask 077 && printf 'OP_SERVICE_ACCOUNT_TOKEN=%s\n' "$token" >"$temporary") &&
        chmod 600 "$temporary" &&
        mv -f "$temporary" "$op_env_path"; then
        :
      else
        status=1
      fi
    fi
  else
    status=1
  fi
  if [[ -n ${temporary:-} && -e $temporary ]]; then
    rm -f -- "$temporary"
  fi
  unset token temporary op_command account reference
  if ((xtrace_enabled)); then
    set -x
  fi
  if ((status != 0)); then
    printf 'Hermes 1Password Service Account could not be loaded.\n' >&2
  fi
  return "$status"
}

dotfiles_hermes_op_command() {
  local configured="${DOTFILES_HERMES_OP_EXECUTABLE:-}"

  if [[ -n $configured ]]; then
    [[ $configured == /* && -x $configured ]] || return 1
    printf '%s\n' "$configured"
    return 0
  fi

  dotfiles_have op || return 1
  command -v op
}

dotfiles_hermes_require_xapi_tools() {
  dotfiles_hermes_op_command >/dev/null ||
    dotfiles_die "1Password CLI (op) is required for Hermes X API credentials."
  dotfiles_have jq || dotfiles_die "jq is required for Hermes X API credentials."
  dotfiles_have python3 || dotfiles_die "python3 is required for Hermes X API token synchronization."
}

dotfiles_hermes_xapi_secret_item() {
  printf '%s\n' "${DOTFILES_HERMES_XAPI_1PASSWORD_ITEM:-Hermes X API MCP}"
}

dotfiles_hermes_xapi_secret_account() {
  printf '%s\n' "${DOTFILES_HERMES_XAPI_1PASSWORD_ACCOUNT:-my.1password.com}"
}

dotfiles_hermes_xapi_secret_vault() {
  printf '%s\n' "${DOTFILES_HERMES_XAPI_1PASSWORD_VAULT:-openclaw}"
}

dotfiles_hermes_extract_xapi_credentials() {
  jq -e -c '
    def field($labels):
      .fields
      | map(select((.label // "") as $label | $labels | index($label)))
      | if length == 1 and (.[0].value | type == "string" and length > 0)
        then .[0].value
        else error("missing required X API OAuth field")
        end;
    {
      client_id: field(["X_API_CLIENT_ID", "client_id", "Client ID"]),
      client_secret: field(["X_API_CLIENT_SECRET", "client_secret", "Client Secret"])
    }
  '
}

dotfiles_hermes_xapi_oauth_item() {
  printf '%s\n' "${DOTFILES_HERMES_XAPI_OAUTH_ITEM:-${DOTFILES_HERMES_XAPI_1PASSWORD_ITEM:-Hermes X API MCP}}"
}

dotfiles_hermes_extract_xapi_refresh_token() {
  jq -e -r '
    .fields
    | map(select((.label // "") as $label |
        ["X_API_REFRESH_TOKEN", "refresh_token", "Refresh Token"] | index($label)))
    | if length == 1 and (.[0].value | type == "string" and length > 0)
      then .[0].value
      else error("missing required X API OAuth refresh token")
      end
  '
}

dotfiles_hermes_read_xapi_refresh_token() {
  local op_command account vault item
  op_command="$(dotfiles_hermes_op_command)" || return 1
  account="$(dotfiles_hermes_xapi_secret_account)"
  vault="$(dotfiles_hermes_xapi_secret_vault)"
  item="$(dotfiles_hermes_xapi_oauth_item)"

  dotfiles_hermes_run_with_service_account_cache \
    "$op_command" item get "$item" --account "$account" --vault "$vault" --format json |
    dotfiles_hermes_extract_xapi_refresh_token
}

dotfiles_hermes_sync_xapi_auth_cache() {
  local data_dir="$1"
  local client_id="$2"
  local client_secret="$3"
  local refresh_token="$4"
  local token_key="${DOTFILES_HERMES_XAPI_OAUTH_TOKEN_KEY:-default}"
  local xurl_dir auth_path temporary
  local client_id_yaml client_secret_yaml refresh_token_yaml token_key_yaml

  xurl_dir="$data_dir/.xurl"
  auth_path="$xurl_dir/auth.yml"
  [[ -d $xurl_dir && ! -L $xurl_dir ]] || return 1
  if [[ ${DOTFILES_HERMES_XAPI_FORCE_CACHE_SYNC:-0} != 1 &&
    -f $auth_path && ! -L $auth_path ]] && grep -q '^ *refresh_token:' "$auth_path"; then
    return 0
  fi
  [[ -n $client_id && $client_id != *$'\n'* && $client_id != *$'\r'* ]] || return 1
  [[ -n $client_secret && $client_secret != *$'\n'* && $client_secret != *$'\r'* ]] || return 1
  [[ -n $refresh_token && $refresh_token != *$'\n'* && $refresh_token != *$'\r'* ]] || return 1
  [[ $token_key =~ ^[A-Za-z0-9._-]+$ ]] || return 1

  client_id_yaml="$(printf '%s' "$client_id" | jq -Rsa .)" || return 1
  client_secret_yaml="$(printf '%s' "$client_secret" | jq -Rsa .)" || return 1
  refresh_token_yaml="$(printf '%s' "$refresh_token" | jq -Rsa .)" || return 1
  token_key_yaml="$(printf '%s' "$token_key" | jq -Rsa .)" || return 1
  temporary="$(mktemp "$xurl_dir/auth.yml.XXXXXX")" || return 1

  if (umask 077 && {
    printf 'apps:\n'
    printf '  default:\n'
    printf '    client_id: %s\n' "$client_id_yaml"
    printf '    client_secret: %s\n' "$client_secret_yaml"
    printf '    oauth2_tokens:\n'
    printf '      %s:\n' "$token_key_yaml"
    printf '        type: oauth2\n'
    printf '        oauth2:\n'
    printf '          refresh_token: %s\n' "$refresh_token_yaml"
    printf 'default_app: default\n'
  } >"$temporary") &&
    chmod 600 "$temporary" &&
    mv -f -- "$temporary" "$auth_path"; then
    :
  else
    rm -f -- "$temporary"
    return 1
  fi
}

dotfiles_hermes_read_xapi_credentials() {
  local op_command account vault item
  op_command="$(dotfiles_hermes_op_command)" || return 1
  account="$(dotfiles_hermes_xapi_secret_account)"
  vault="$(dotfiles_hermes_xapi_secret_vault)"
  item="$(dotfiles_hermes_xapi_secret_item)"

  dotfiles_hermes_run_with_service_account_cache \
    "$op_command" item get "$item" --account "$account" --vault "$vault" --format json |
    dotfiles_hermes_extract_xapi_credentials
}

dotfiles_hermes_with_xapi_credentials() {
  local credentials client_id client_secret status=0 xtrace_enabled=0

  dotfiles_hermes_op_command >/dev/null ||
    dotfiles_die "1Password CLI (op) is required for Hermes X API credentials."
  dotfiles_have jq || dotfiles_die "jq is required for Hermes X API credentials."
  dotfiles_hermes_prepare_service_account_environment || return 1

  if [[ $- == *x* ]]; then
    xtrace_enabled=1
    set +x
  fi
  if credentials="$(dotfiles_hermes_read_xapi_credentials)" &&
    client_id="$(printf '%s\n' "$credentials" | jq -r '.client_id')" &&
    client_secret="$(printf '%s\n' "$credentials" | jq -r '.client_secret')"; then
    X_API_CLIENT_ID="$client_id" X_API_CLIENT_SECRET="$client_secret" "$@" || status=$?
  else
    status=1
  fi
  unset credentials client_id client_secret
  if ((xtrace_enabled)); then
    set -x
  fi
  return "$status"
}

dotfiles_hermes_with_xapi_credentials_and_cache() {
  local credentials client_id client_secret refresh_token status=0 xtrace_enabled=0

  dotfiles_hermes_op_command >/dev/null ||
    dotfiles_die "1Password CLI (op) is required for Hermes X API credentials."
  dotfiles_have jq || dotfiles_die "jq is required for Hermes X API credentials."
  dotfiles_hermes_prepare_service_account_environment || return 1

  if [[ $- == *x* ]]; then
    xtrace_enabled=1
    set +x
  fi
  if credentials="$(dotfiles_hermes_read_xapi_credentials)" &&
    client_id="$(printf '%s\n' "$credentials" | jq -r '.client_id')" &&
    client_secret="$(printf '%s\n' "$credentials" | jq -r '.client_secret')" &&
    refresh_token="$(dotfiles_hermes_read_xapi_refresh_token)" &&
    dotfiles_hermes_sync_xapi_auth_cache "$(dotfiles_hermes_data_dir)" \
      "$client_id" "$client_secret" "$refresh_token"; then
    X_API_CLIENT_ID="$client_id" X_API_CLIENT_SECRET="$client_secret" "$@" || status=$?
  else
    status=1
  fi
  unset credentials client_id client_secret refresh_token
  if ((xtrace_enabled)); then
    set -x
  fi
  return "$status"
}

dotfiles_hermes_probe_xapi_token() {
  local docker_runner="$1"
  local compose_file="$2"
  local probe_output probe_status

  if probe_output="$("$docker_runner" compose -f "$compose_file" run --rm --no-deps \
    --entrypoint /bin/sh xapi-mcp \
    -lc 'CLIENT_ID="$X_API_CLIENT_ID" CLIENT_SECRET="$X_API_CLIENT_SECRET" node_modules/.bin/xurl token >/dev/null' 2>&1)"; then
    return 0
  else
    probe_status=$?
  fi
  if printf '%s\n' "$probe_output" | grep -Eqi \
    'Auth Error: TokenNotFound|oauth2 token not found|invalid_grant|invalid_client|unauthorized_client'; then
    return 79
  fi
  return "$probe_status"
}

dotfiles_hermes_restore_xapi_auth_cache() {
  local auth_path="$1" snapshot_path="$2" cache_existed="$3"

  if ((cache_existed)); then
    chmod 600 "$snapshot_path" && mv -f -- "$snapshot_path" "$auth_path"
  else
    rm -f -- "$auth_path" "$snapshot_path"
  fi
}

dotfiles_hermes_sync_xapi_refresh_token_to_onepassword() {
  local data_dir cache_path item_file template_file account vault item op_command status=0 render_status=0

  data_dir="$(dotfiles_hermes_data_dir)"
  cache_path="$data_dir/.xurl/auth.yml"
  [[ -f $cache_path && ! -L $cache_path ]] || return 1
  [[ $(stat -c '%a' "$cache_path" 2>/dev/null || stat -f '%Lp' "$cache_path") == 600 ]] || return 1
  op_command="$(dotfiles_hermes_op_command)" || return 1
  account="$(dotfiles_hermes_xapi_secret_account)"
  vault="$(dotfiles_hermes_xapi_secret_vault)"
  item="$(dotfiles_hermes_xapi_oauth_item)"
  item_file="$(mktemp "$data_dir/.xapi-item.XXXXXX")" || return 1
  template_file="$(mktemp "$data_dir/.xapi-template.XXXXXX")" || {
    rm -f -- "$item_file"
    return 1
  }
  chmod 600 "$item_file" "$template_file" || status=1
  if ((status == 0)); then
    dotfiles_hermes_run_with_service_account_cache \
      "$op_command" item get "$item" --account "$account" --vault "$vault" --format json >"$item_file" || status=$?
  fi
  if ((status == 0)); then
    if python3 - "$item_file" "$cache_path" >"$template_file" <<'PY'
import json
import re
import sys

item_path, cache_path = sys.argv[1:]
with open(item_path, encoding="utf-8") as item_file:
    item = json.load(item_file)
with open(cache_path, encoding="utf-8") as cache_file:
    cache = cache_file.read()
match = re.search(r'(?m)^\s+refresh_token:\s*(?:"([^"]+)"|\x27([^\x27]+)\x27|([^\s#]+))\s*$', cache)
if match is None:
    raise SystemExit(1)
refresh_token = next(value for value in match.groups() if value is not None)
fields = [
    field for field in item.get("fields", [])
    if field.get("label") == "X_API_REFRESH_TOKEN"
    and (field.get("section") or {}).get("label") == "Refresh Token"
]
if len(fields) != 1:
    raise SystemExit(1)
if fields[0].get("value") == refresh_token:
    raise SystemExit(3)
fields[0]["value"] = refresh_token
sys.stdout.write(json.dumps(item, separators=(",", ":")))
PY
    then
      render_status=0
    else
      render_status=$?
    fi
    if ((render_status == 3)); then
      status=0
    else
      status=$render_status
    fi
  fi
  if ((status == 0 && render_status == 0)); then
    dotfiles_hermes_run_with_service_account_cache \
      "$op_command" item edit "$item" --account "$account" --vault "$vault" --template "$template_file" >/dev/null || status=$?
  fi
  rm -f -- "$item_file" "$template_file"
  return "$status"
}

dotfiles_hermes_ensure_xapi_auth() {
  local docker_runner="$1"
  local compose_file="$2"
  local data_dir xurl_dir auth_path snapshot_path cache_existed=0 probe_status sync_status

  data_dir="$(dotfiles_hermes_data_dir)"
  xurl_dir="$data_dir/.xurl"
  auth_path="$xurl_dir/auth.yml"
  [[ -d $xurl_dir && ! -L $xurl_dir ]] || return 1
  snapshot_path="$(mktemp "$xurl_dir/auth.yml.rollback.XXXXXX")" || return 1
  if [[ -e $auth_path || -L $auth_path ]]; then
    if [[ ! -f $auth_path || -L $auth_path ]] || ! cp -p -- "$auth_path" "$snapshot_path"; then
      rm -f -- "$snapshot_path"
      return 1
    fi
    cache_existed=1
  fi

  if dotfiles_hermes_with_xapi_credentials_and_cache \
    dotfiles_hermes_probe_xapi_token "$docker_runner" "$compose_file"; then
    if dotfiles_hermes_sync_xapi_refresh_token_to_onepassword; then
      rm -f -- "$snapshot_path"
      return 0
    else
      sync_status=$?
    fi
    rm -f -- "$snapshot_path"
    return "$sync_status"
  else
    probe_status=$?
  fi
  if ((probe_status != 79)); then
    dotfiles_hermes_restore_xapi_auth_cache "$auth_path" "$snapshot_path" "$cache_existed" || true
    return "$probe_status"
  fi

  if DOTFILES_HERMES_XAPI_FORCE_CACHE_SYNC=1 \
    dotfiles_hermes_with_xapi_credentials_and_cache \
    dotfiles_hermes_probe_xapi_token "$docker_runner" "$compose_file"; then
    if dotfiles_hermes_sync_xapi_refresh_token_to_onepassword; then
      rm -f -- "$snapshot_path"
      return 0
    else
      sync_status=$?
    fi
    rm -f -- "$snapshot_path"
    return "$sync_status"
  else
    probe_status=$?
  fi
  dotfiles_hermes_restore_xapi_auth_cache "$auth_path" "$snapshot_path" "$cache_existed" || true
  if ((probe_status != 79)); then
    return "$probe_status"
  fi

  printf '%s\n' \
    'Hermes X API OAuth is invalid. Run task hermes:xapi:setup to reauthorize it.' >&2
  return 1
}
