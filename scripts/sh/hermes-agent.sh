#!/usr/bin/env bash

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

dotfiles_hermes_read_service_account_token() {
  local op_command="$1" account="$2" reference="$3" result_variable="$4"
  local data_dir temporary pid timeout_seconds elapsed_seconds=0 poll read_token status=1 timed_out=0

  data_dir="$(dotfiles_hermes_data_dir)"
  timeout_seconds="${DOTFILES_HERMES_OP_READ_TIMEOUT_SECONDS:-20}"
  [[ $timeout_seconds =~ ^[1-9][0-9]*$ ]] || timeout_seconds=20
  temporary="$(mktemp "$data_dir/.op.read.XXXXXX")" || return 1
  chmod 600 "$temporary" || {
    rm -f -- "$temporary"
    return 1
  }

  "$op_command" --account "$account" read "$reference" >"$temporary" 2>/dev/null &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    for ((poll = 0; poll < 10; poll++)); do
      /bin/sleep 0.1
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
  if dotfiles_hermes_read_service_account_token "$op_command" "$account" "$reference" token &&
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
  elif dotfiles_hermes_validate_service_account_environment_cache "$op_env_path"; then
    printf 'Hermes 1Password Service Account could not be loaded; using existing Hermes service-account environment.\n' >&2
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

dotfiles_hermes_require_secret_tools() {
  dotfiles_hermes_op_command >/dev/null ||
    dotfiles_die "1Password CLI (op) is required for Hermes bootstrap."
  dotfiles_have jq || dotfiles_die "jq is required for Hermes bootstrap."
  dotfiles_have curl || dotfiles_die "curl is required for Hermes readiness checks."
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

dotfiles_hermes_read_xapi_credentials() {
  local op_command account vault item
  op_command="$(dotfiles_hermes_op_command)" || return 1
  account="$(dotfiles_hermes_xapi_secret_account)"
  vault="$(dotfiles_hermes_xapi_secret_vault)"
  item="$(dotfiles_hermes_xapi_secret_item)"

  "$op_command" signin --account "$account" >/dev/null
  "$op_command" item get "$item" --account "$account" --vault "$vault" --format json |
    dotfiles_hermes_extract_xapi_credentials
}

dotfiles_hermes_with_xapi_credentials() {
  local credentials client_id client_secret status=0 xtrace_enabled=0

  dotfiles_hermes_op_command >/dev/null ||
    dotfiles_die "1Password CLI (op) is required for Hermes X API credentials."
  dotfiles_have jq || dotfiles_die "jq is required for Hermes X API credentials."

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

dotfiles_hermes_validate_secret_plan() {
  jq -Ssce '
    if length == 1 and (.[0] | type == "object") then .[0] else false end
    |
    . as $plan | (
    def nonblank_string:
      type == "string" and test("[^[:space:]]") and test("^[^[:cntrl:]]+$");
    def field:
      type == "object"
      and ((keys | sort == ["canonical_name", "labels"]) or
        (keys | sort == ["canonical_name", "labels", "reference"]))
      and (.canonical_name | nonblank_string)
      and (.labels | type == "array" and length > 0 and all(.[]; nonblank_string))
      and ((has("reference") | not) or (.reference | nonblank_string));
    def plan_item:
      type == "object"
      and (keys | sort == ["account", "fields", "item", "key", "vault"])
      and (.key | nonblank_string)
      and (.account | nonblank_string)
      and (.vault | nonblank_string)
      and (.item | nonblank_string)
      and (.fields | type == "array" and length > 0 and all(.[]; field))
      and ((.fields | map(.canonical_name) | unique | length) == (.fields | length));
    type == "object"
    and (keys | sort == ["items", "schema_version"])
    and (.schema_version == 1)
    and (.items | type == "array" and length == 10)
    and ([.items[] | {key, account, vault, item}] == [
      {"key":"dashboard","account":"my.1password.com","vault":"openclaw","item":"Hermes Agent Dashboard"},
      {"key":"github","account":"my.1password.com","vault":"openclaw","item":"GitHubUsedOpenClawPAT"},
      {"key":"google_calendar","account":"my.1password.com","vault":"Private","item":"Google Calendar MCP"},
      {"key":"discord_default","account":"my.1password.com","vault":"openclaw","item":"Master"},
      {"key":"discord_rick","account":"my.1password.com","vault":"openclaw","item":"Rick"},
      {"key":"discord_hoffman","account":"my.1password.com","vault":"openclaw","item":"Hoffman"},
      {"key":"discord_risarisa","account":"my.1password.com","vault":"openclaw","item":"RisaRisa"},
      {"key":"discord_nancy","account":"my.1password.com","vault":"openclaw","item":"Nancy"},
      {"key":"discord_kuroda","account":"my.1password.com","vault":"openclaw","item":"Kuroda"},
      {"key":"discord_shiraishi","account":"my.1password.com","vault":"openclaw","item":"Shiraishi"}
    ])
    and ([.items[].key] | unique | length == 10)
    and all(.items[]; plan_item)
    ) as $valid
    | if $valid then $plan else false end
  '
}

dotfiles_hermes_secret_plan() {
  local docker_runner="$1"
  local compose_file="$2"
  local compact_plan

  dotfiles_hermes_require_secret_tools
  set -o pipefail
  if ! compact_plan="$("$docker_runner" compose -f "$compose_file" run --rm --no-deps -T hermes-bootstrap secret-plan | dotfiles_hermes_validate_secret_plan)"; then
    dotfiles_die "Hermes bootstrap secret plan is invalid."
  fi
  printf '%s\n' "$compact_plan"
}

dotfiles_hermes_emit_secret_item() {
  local op_command="$1"
  local key="$2"
  local account="$3"
  local vault="$4"
  local item="$5"
  local item_record status=0 xtrace_enabled=0

  if [[ $- == *x* ]]; then
    xtrace_enabled=1
    set +x
  fi
  if ! item_record="$(
    "$op_command" item get "$item" --account "$account" --vault "$vault" --format json |
      jq -ce --arg key "$key" 'if type == "object" then {type: "item", key: $key, item: .} else error("1Password item is not an object") end'
  )"; then
    status=1
  elif ! printf '%s\n' "$item_record"; then
    status=141
  fi
  unset item_record
  if ((xtrace_enabled)); then
    set -x
  fi
  return "$status"
}

dotfiles_hermes_emit_secret_payload() {
  local compact_plan="$1"
  local item_plan key account vault item op_command

  op_command="$(dotfiles_hermes_op_command)" || return 1
  printf '%s\n' '{"type":"header","schema_version":1}' || return 141
  while IFS= read -r item_plan; do
    key="$(printf '%s\n' "$item_plan" | jq -r '.key')"
    account="$(printf '%s\n' "$item_plan" | jq -r '.account')"
    vault="$(printf '%s\n' "$item_plan" | jq -r '.vault')"
    item="$(printf '%s\n' "$item_plan" | jq -r '.item')"
    dotfiles_hermes_emit_secret_item "$op_command" "$key" "$account" "$vault" "$item" || return $?
  done < <(printf '%s\n' "$compact_plan" | jq -c '.items[]')
  printf '%s\n' '{"type":"end"}' || return 141
}

dotfiles_hermes_run_bootstrap() {
  local docker_runner="$1"
  local compose_file="$2"
  local compact_plan producer_status docker_status
  local -a statuses

  compact_plan="$(dotfiles_hermes_secret_plan "$docker_runner" "$compose_file")" || return 1
  set -o pipefail
  if dotfiles_hermes_emit_secret_payload "$compact_plan" |
    "$docker_runner" compose -f "$compose_file" run --rm --no-deps -T hermes-bootstrap apply; then
    return 0
  else
    statuses=("${PIPESTATUS[@]}")
    producer_status="${statuses[0]:-1}"
    docker_status="${statuses[1]:-1}"
    if ((producer_status == 141 && docker_status != 0)); then
      return "$docker_status"
    fi
    if ((producer_status != 0)); then
      return 1
    fi
    return "$docker_status"
  fi
}

dotfiles_hermes_wait_for_api() {
  local attempts delay_seconds timeout_seconds port url attempt
  attempts="${HERMES_API_READY_ATTEMPTS:-30}"
  delay_seconds="${HERMES_API_READY_DELAY_SECONDS:-2}"
  timeout_seconds="${HERMES_API_PROBE_TIMEOUT_SECONDS:-2}"
  port="${HERMES_API_PORT:-8642}"

  [[ $attempts =~ ^[1-9][0-9]*$ ]] || attempts=30
  [[ $delay_seconds =~ ^[0-9]+$ ]] || delay_seconds=2
  [[ $timeout_seconds =~ ^[1-9][0-9]*$ ]] || timeout_seconds=2
  url="http://127.0.0.1:${port}/health"

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if curl --fail --silent --show-error --max-time "$timeout_seconds" "$url" >/dev/null 2>&1; then
      return 0
    fi
    if ((attempt < attempts)); then
      sleep "$delay_seconds"
    fi
  done

  printf 'Hermes API did not become ready after %s attempts.\n' "$attempts" >&2
  return 1
}

dotfiles_hermes_show_compose_diagnostics() {
  local docker_runner="$1"
  local compose_file="$2"

  "$docker_runner" compose -f "$compose_file" ps --all >&2 || true
}

dotfiles_hermes_start_stack() {
  local docker_runner="$1"
  local compose_file="$2"
  local status

  dotfiles_hermes_require_secret_tools
  dotfiles_hermes_prepare_runtime_home
  dotfiles_hermes_prepare_service_account_environment ||
    dotfiles_die "Hermes 1Password Service Account is unavailable."

  if "$docker_runner" compose -f "$compose_file" config --quiet; then
    :
  else
    status=$?
    dotfiles_hermes_show_compose_diagnostics "$docker_runner" "$compose_file"
    return "$status"
  fi
  if "$docker_runner" compose -f "$compose_file" build hermes hermes-bootstrap xapi-mcp; then
    :
  else
    status=$?
    dotfiles_hermes_show_compose_diagnostics "$docker_runner" "$compose_file"
    return "$status"
  fi
  if "$docker_runner" compose -f "$compose_file" stop hermes; then
    :
  else
    status=$?
    dotfiles_hermes_show_compose_diagnostics "$docker_runner" "$compose_file"
    return "$status"
  fi
  if dotfiles_hermes_run_bootstrap "$docker_runner" "$compose_file"; then
    :
  else
    status=$?
    dotfiles_hermes_show_compose_diagnostics "$docker_runner" "$compose_file"
    return "$status"
  fi
  if dotfiles_hermes_with_xapi_credentials "$docker_runner" compose -f "$compose_file" up -d --force-recreate; then
    :
  else
    status=$?
    dotfiles_hermes_show_compose_diagnostics "$docker_runner" "$compose_file"
    return "$status"
  fi
  if dotfiles_hermes_wait_for_api; then
    return 0
  else
    status=$?
    dotfiles_hermes_show_compose_diagnostics "$docker_runner" "$compose_file"
    return "$status"
  fi
}
