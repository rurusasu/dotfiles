#!/usr/bin/env bash

dotfiles_hermes_agent_script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
unset dotfiles_hermes_agent_script_dir

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

dotfiles_hermes_storage_volume_name() {
  local volume_name="${HERMES_DATA_VOLUME:-hermes-data}"

  [[ $volume_name =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || return 1
  printf '%s\n' "$volume_name"
}

dotfiles_hermes_storage_volume_label() {
  local docker_runner="$1" volume_name="$2" label="$3"

  "$docker_runner" volume inspect --format "{{ index .Labels \"$label\" }}" "$volume_name"
}

dotfiles_hermes_storage_lock_name() {
  local volume_name="$1"

  python3 -c 'import hashlib, sys; print("dotfiles-hermes-storage-" + hashlib.sha256(sys.argv[1].encode()).hexdigest()[:20])' "$volume_name"
}

dotfiles_hermes_storage_volume_ready() {
  local docker_runner="$1" volume_name="$2" volume_token="$3"

  "$docker_runner" run --rm \
    --entrypoint python \
    --mount "type=volume,src=$volume_name,dst=/target,readonly" \
    local/hermes-agent-gh:latest \
    -c 'import pathlib, stat, sys; marker=pathlib.Path("/target/.dotfiles-hermes-storage-ready-v1"); expected=f"version=1\nvolume_token={sys.argv[1]}\n";
try:
 mode=marker.lstat().st_mode
except FileNotFoundError:
 raise SystemExit(3)
except OSError as error:
 print(f"Hermes ready marker could not be inspected: {error}", file=sys.stderr); raise SystemExit(2)
if stat.S_ISLNK(mode) or not stat.S_ISREG(mode): raise SystemExit(3)
try:
 actual=marker.read_text(encoding="utf-8")
except (OSError, UnicodeError) as error:
 print(f"Hermes ready marker could not be read: {error}", file=sys.stderr); raise SystemExit(2)
raise SystemExit(0 if actual == expected else 3)' \
    "$volume_token"
}

dotfiles_hermes_converge_storage_ownership() {
  local docker_runner="$1" volume_name="$2"

  "$docker_runner" run --rm \
    --network none \
    --read-only \
    --cap-drop ALL \
    --cap-add CHOWN \
    --cap-add DAC_OVERRIDE \
    --security-opt no-new-privileges:true \
    --user 0:0 \
    --entrypoint /usr/local/bin/hermes-storage-ownership \
    --mount "type=volume,src=$volume_name,dst=/target" \
    local/hermes-agent-gh:latest \
    --target /target --uid 10000 --gid 10000
}

dotfiles_hermes_release_storage_lock() {
  local docker_runner="$1" lock_id="$2" heartbeat_pid="${3:-}" heartbeat_path="${4:-}"
  local release_status=0

  if [[ $heartbeat_pid =~ ^[1-9][0-9]*$ ]]; then
    kill "$heartbeat_pid" >/dev/null 2>&1 || true
    wait "$heartbeat_pid" 2>/dev/null || true
  fi
  "$docker_runner" rm -f "$lock_id" >/dev/null 2>&1 || release_status=$?
  if [[ -n $heartbeat_path ]]; then
    rm -f -- "$heartbeat_path"
  fi
  return "$release_status"
}

dotfiles_hermes_storage_lock_state() {
  local docker_runner="$1" lock_name="$2" lock_label="$3" token_label="$4" created_label="$5"

  "$docker_runner" inspect --format \
    "{{ .Id }}|{{ index .Config.Labels \"$lock_label\" }}|{{ index .Config.Labels \"$token_label\" }}|{{ index .Config.Labels \"$created_label\" }}|{{ .State.Status }}" \
    "$lock_name"
}

dotfiles_hermes_create_storage_lock() {
  local docker_runner="$1" lock_name="$2" lock_label="$3" token_label="$4" created_label="$5"
  local volume_token="$6" created_at="$7" heartbeat_path="$8"

  "$docker_runner" create \
    --name "$lock_name" \
    --label "$lock_label=1" \
    --label "$token_label=$volume_token" \
    --label "$created_label=$created_at" \
    --network none \
    --read-only \
    --cap-drop ALL \
    --security-opt no-new-privileges:true \
    --entrypoint python \
    --mount "type=bind,src=$heartbeat_path,dst=/lease,readonly" \
    local/hermes-agent-gh:latest \
    -c 'import os, sys, time
path, timeout = sys.argv[1], float(sys.argv[2])
while True:
 try:
  age = time.time() - os.stat(path).st_mtime
 except OSError:
  raise SystemExit(1)
 if age > timeout:
  raise SystemExit(0)
 time.sleep(1)' \
    /lease 30
}

dotfiles_hermes_start_storage_lock_lease() {
  local docker_runner="$1" lock_id="$2" heartbeat_path="$3" result_variable="$4"
  local owner_pid="${BASHPID:-$$}"
  local interval="${DOTFILES_HERMES_STORAGE_HEARTBEAT_INTERVAL_SECONDS:-5}"

  [[ $interval =~ ^[0-9]+([.][0-9]+)?$ ]] || interval=5
  "$docker_runner" start "$lock_id" >/dev/null || return $?
  (
    while kill -0 "$owner_pid" >/dev/null 2>&1; do
      touch -m -- "$heartbeat_path" || exit 1
      /bin/sleep "$interval" || exit 1
    done
  ) >/dev/null 2>&1 &
  printf -v "$result_variable" '%s' "$!"
}

dotfiles_hermes_seed_storage_volume() {
  local docker_runner="$1" data_dir="$2" volume_name="$3" volume_token="$4"

  "$docker_runner" run --rm \
    --entrypoint /usr/local/bin/hermes-storage-seed \
    --mount "type=bind,src=$data_dir,dst=/source,readonly" \
    --mount "type=volume,src=$volume_name,dst=/target" \
    local/hermes-agent-gh:latest \
    --source /source --destination /target \
    --ready-token "$volume_token" --replace-incomplete
}

dotfiles_hermes_initialize_storage_volume() {
  local docker_runner="$1"
  local volume_name data_dir volume_schema volume_token actual_schema actual_token lock_name lock_id
  local volume_status probe_status seed_status ownership_status release_status
  local schema_label="com.rurusasu.dotfiles.hermes-storage.schema"
  local token_label="com.rurusasu.dotfiles.hermes-storage.init-token"
  local lock_label="com.rurusasu.dotfiles.hermes-storage.lock"
  local lock_created_label="com.rurusasu.dotfiles.hermes-storage.lock-created-at"
  local lock_state stale_lock_id stale_lock_marker stale_lock_token stale_lock_created stale_lock_status
  local lock_created_at now reclaim_stale=0 heartbeat_token heartbeat_path heartbeat_pid=""

  volume_name="$(dotfiles_hermes_storage_volume_name)" ||
    dotfiles_die "HERMES_DATA_VOLUME contains an invalid Docker volume name."
  data_dir="$(dotfiles_hermes_data_dir)"

  if volume_schema="$(dotfiles_hermes_storage_volume_label "$docker_runner" "$volume_name" "$schema_label" 2>/dev/null)"; then
    if [[ $volume_schema != 1 ]]; then
      printf 'Legacy Hermes Docker data volume already exists; leaving it untouched: %s\n' "$volume_name" >&2
      return 0
    fi
    volume_token="$(dotfiles_hermes_storage_volume_label "$docker_runner" "$volume_name" "$token_label" 2>/dev/null)" || return $?
  else
    volume_status=$?
    ((volume_status == 1)) || return "$volume_status"
    volume_token="$(python3 -c 'import uuid; print(uuid.uuid4().hex)')" || return $?
    "$docker_runner" volume create \
      --label "$schema_label=1" \
      --label "$token_label=$volume_token" \
      "$volume_name" >/dev/null || return $?
  fi

  [[ $volume_token =~ ^[0-9a-f]{32}$ ]] || {
    printf 'Hermes Docker data volume has an invalid initialization token: %s\n' "$volume_name" >&2
    return 1
  }
  lock_name="$(dotfiles_hermes_storage_lock_name "$volume_name")" || return $?
  heartbeat_token="$(python3 -c 'import uuid; print(uuid.uuid4().hex)')" || return $?
  heartbeat_path="$data_dir/.dotfiles-hermes-storage-lease-$heartbeat_token"
  (umask 077 && : >"$heartbeat_path") || return $?
  lock_created_at="$(python3 -c 'import time; print(int(time.time()))')" || {
    seed_status=$?
    rm -f -- "$heartbeat_path"
    return "$seed_status"
  }
  if ! lock_id="$(dotfiles_hermes_create_storage_lock \
    "$docker_runner" "$lock_name" "$lock_label" "$token_label" "$lock_created_label" \
    "$volume_token" "$lock_created_at" "$heartbeat_path" 2>/dev/null)"; then
    lock_state="$(dotfiles_hermes_storage_lock_state \
      "$docker_runner" "$lock_name" "$lock_label" "$token_label" "$lock_created_label" 2>/dev/null)" || lock_state=""
    IFS='|' read -r stale_lock_id stale_lock_marker stale_lock_token stale_lock_created stale_lock_status <<<"$lock_state"
    if [[ $stale_lock_id =~ ^[0-9a-f]{12,64}$ && $stale_lock_marker == 1 && $stale_lock_token == "$volume_token" ]]; then
      case "$stale_lock_status" in
      exited | dead) reclaim_stale=1 ;;
      created)
        now="$(python3 -c 'import time; print(int(time.time()))')" || {
          seed_status=$?
          rm -f -- "$heartbeat_path"
          return "$seed_status"
        }
        if [[ $stale_lock_created =~ ^[0-9]{1,12}$ ]] && ((now - stale_lock_created >= 30)); then
          reclaim_stale=1
        fi
        ;;
      esac
    fi
    if ((reclaim_stale == 0)); then
      rm -f -- "$heartbeat_path"
      printf 'Hermes Docker data volume initialization is already locked: %s\n' "$volume_name" >&2
      return 1
    fi
    if dotfiles_hermes_release_storage_lock "$docker_runner" "$stale_lock_id"; then
      :
    else
      release_status=$?
      rm -f -- "$heartbeat_path"
      return "$release_status"
    fi
    lock_created_at="$(python3 -c 'import time; print(int(time.time()))')" || {
      seed_status=$?
      rm -f -- "$heartbeat_path"
      return "$seed_status"
    }
    if lock_id="$(dotfiles_hermes_create_storage_lock \
      "$docker_runner" "$lock_name" "$lock_label" "$token_label" "$lock_created_label" \
      "$volume_token" "$lock_created_at" "$heartbeat_path")"; then
      :
    else
      seed_status=$?
      rm -f -- "$heartbeat_path"
      return "$seed_status"
    fi
  fi
  [[ $lock_id =~ ^[0-9a-f]{12,64}$ ]] || {
    rm -f -- "$heartbeat_path"
    return 1
  }
  if dotfiles_hermes_start_storage_lock_lease \
    "$docker_runner" "$lock_id" "$heartbeat_path" heartbeat_pid; then
    :
  else
    seed_status=$?
    dotfiles_hermes_release_storage_lock "$docker_runner" "$lock_id" "" "$heartbeat_path" || true
    return "$seed_status"
  fi

  actual_schema="$(dotfiles_hermes_storage_volume_label "$docker_runner" "$volume_name" "$schema_label" 2>/dev/null)" || {
    dotfiles_hermes_release_storage_lock "$docker_runner" "$lock_id" "$heartbeat_pid" "$heartbeat_path" || true
    printf 'Hermes Docker data volume identity could not be verified while locked: %s\n' "$volume_name" >&2
    return 1
  }
  actual_token="$(dotfiles_hermes_storage_volume_label "$docker_runner" "$volume_name" "$token_label" 2>/dev/null)" || {
    dotfiles_hermes_release_storage_lock "$docker_runner" "$lock_id" "$heartbeat_pid" "$heartbeat_path" || true
    printf 'Hermes Docker data volume identity could not be verified while locked: %s\n' "$volume_name" >&2
    return 1
  }
  if [[ $actual_schema != 1 || $actual_token != "$volume_token" ]]; then
    dotfiles_hermes_release_storage_lock "$docker_runner" "$lock_id" "$heartbeat_pid" "$heartbeat_path" || true
    printf 'Hermes Docker data volume changed before its lock was acquired; refusing to access it: %s\n' "$volume_name" >&2
    return 1
  fi

  if dotfiles_hermes_storage_volume_ready "$docker_runner" "$volume_name" "$volume_token"; then
    if dotfiles_hermes_converge_storage_ownership "$docker_runner" "$volume_name"; then
      dotfiles_hermes_release_storage_lock "$docker_runner" "$lock_id" "$heartbeat_pid" "$heartbeat_path" || return $?
      printf 'Hermes Docker data volume is ready: %s\n' "$volume_name" >&2
      return 0
    else
      ownership_status=$?
    fi
    if dotfiles_hermes_release_storage_lock "$docker_runner" "$lock_id" "$heartbeat_pid" "$heartbeat_path"; then
      printf 'Hermes Docker data volume ownership convergence failed with status %s: %s\n' \
        "$ownership_status" "$volume_name" >&2
      return "$ownership_status"
    fi
    release_status=$?
    printf 'Hermes Docker data volume ownership convergence failed with status %s and its lock could not be released: %s\n' \
      "$ownership_status" "$volume_name" >&2
    return "$release_status"
  else
    probe_status=$?
  fi
  if ((probe_status != 3)); then
    if dotfiles_hermes_release_storage_lock "$docker_runner" "$lock_id" "$heartbeat_pid" "$heartbeat_path"; then
      printf 'Hermes Docker data volume ready marker probe failed with status %s; preserving it unchanged: %s\n' \
        "$probe_status" "$volume_name" >&2
      return "$probe_status"
    else
      release_status=$?
      printf 'Hermes Docker data volume ready marker probe failed with status %s and its lock could not be released: %s\n' \
        "$probe_status" "$volume_name" >&2
      return "$release_status"
    fi
  fi

  if dotfiles_hermes_seed_storage_volume "$docker_runner" "$data_dir" "$volume_name" "$volume_token"; then
    if dotfiles_hermes_storage_volume_ready "$docker_runner" "$volume_name" "$volume_token"; then
      if dotfiles_hermes_converge_storage_ownership "$docker_runner" "$volume_name"; then
        dotfiles_hermes_release_storage_lock "$docker_runner" "$lock_id" "$heartbeat_pid" "$heartbeat_path" || return $?
        printf 'Hermes Docker data volume initialized: %s\n' "$volume_name" >&2
        return 0
      else
        ownership_status=$?
      fi
      if dotfiles_hermes_release_storage_lock "$docker_runner" "$lock_id" "$heartbeat_pid" "$heartbeat_path"; then
        printf 'Hermes Docker data volume ownership convergence failed with status %s: %s\n' \
          "$ownership_status" "$volume_name" >&2
        return "$ownership_status"
      fi
      release_status=$?
      printf 'Hermes Docker data volume ownership convergence failed with status %s and its lock could not be released: %s\n' \
        "$ownership_status" "$volume_name" >&2
      return "$release_status"
    else
      probe_status=$?
    fi
    if ((probe_status == 3)); then
      seed_status=1
      printf 'Hermes Docker data volume seed completed without its ready marker: %s\n' "$volume_name" >&2
    else
      seed_status=$probe_status
      printf 'Hermes Docker data volume post-seed ready marker probe failed with status %s: %s\n' \
        "$probe_status" "$volume_name" >&2
    fi
  else
    seed_status=$?
  fi

  if dotfiles_hermes_release_storage_lock "$docker_runner" "$lock_id" "$heartbeat_pid" "$heartbeat_path"; then
    printf 'Hermes Docker data volume remains incomplete and will be safely replaced on retry: %s\n' "$volume_name" >&2
    return "$seed_status"
  else
    release_status=$?
  fi
  printf 'Hermes Docker data volume initialization failed and its lock could not be released: %s (seed status %s, release status %s)\n' \
    "$volume_name" "$seed_status" "$release_status" >&2
  return "$release_status"
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

dotfiles_hermes_require_secret_tools() {
  dotfiles_hermes_op_command >/dev/null ||
    dotfiles_die "1Password CLI (op) is required for Hermes bootstrap."
  dotfiles_have jq || dotfiles_die "jq is required for Hermes bootstrap."
  dotfiles_have curl || dotfiles_die "curl is required for Hermes readiness checks."
  dotfiles_have python3 || dotfiles_die "python3 is required for Hermes storage initialization."
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

dotfiles_hermes_validate_secret_plan() {
  local expected_account="${1:-}"
  local expected_manifest_sha256="${2:-}"
  jq -Ssce \
    --arg expected_account "$expected_account" \
    --arg expected_manifest_sha256 "$expected_manifest_sha256" '
    def nonblank_string:
      type == "string" and test("[^[:space:]]") and test("^[^[:cntrl:]]+$");
    def env_name:
      type == "string" and test("^[A-Z_][A-Z0-9_]*$");
    def field:
      type == "object"
      and ((keys - ["canonical_name", "labels", "reference", "environment"]) | length == 0)
      and (has("canonical_name") and has("labels"))
      and (.canonical_name | nonblank_string)
      and (.labels | type == "array" and length > 0 and all(.[]; nonblank_string))
      and ((has("reference") | not) or (.reference | nonblank_string))
      and ((.environment // []) | type == "array" and all(.[]; env_name));
    def plan_item:
      type == "object"
      and (keys | sort == ["account", "fields", "item", "key", "vault"])
      and (.key | nonblank_string)
      and (.account | nonblank_string)
      and (.vault | nonblank_string)
      and (.item | nonblank_string)
      and (.fields | type == "array" and length > 0 and all(.[]; field))
      and ((.fields | map(.canonical_name) | unique | length) == (.fields | length));
    (if length == 1 and (.[0] | type == "object") then .[0] else false end)
    | if . == false then false
      elif (
        type == "object"
        and (keys | sort == ["items", "manifest_sha256", "schema_version"])
        and (.schema_version == 1)
        and (.manifest_sha256 | type == "string" and test("^[a-f0-9]{64}$"))
        and ($expected_manifest_sha256 == "" or .manifest_sha256 == $expected_manifest_sha256)
        and (.items | type == "array" and length > 0)
        and (([.items[].key] | unique | length) == (.items | length))
        and all(.items[];
          (($expected_account == "" or .account == $expected_account)
            and .vault == "openclaw"))
        and all(.items[]; plan_item)
      ) then . else false end
  '
}

dotfiles_hermes_bootstrap_manifest_path() {
  local compose_file="$1" compose_directory

  compose_directory="$(cd -- "$(dirname -- "$compose_file")" && pwd)" || return 1
  printf '%s\n' "$compose_directory/../hermes-agent/bootstrap-manifest.yaml"
}

dotfiles_hermes_bootstrap_manifest_sha256() {
  local manifest_path="$1"

  [[ -f $manifest_path && ! -L $manifest_path ]] || return 1
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$manifest_path" | awk '{print $1}'
  else
    shasum -a 256 "$manifest_path" | awk '{print $1}'
  fi
}

dotfiles_hermes_secret_plan() {
  local docker_runner="$1"
  local compose_file="$2"
  local compact_plan manifest_path manifest_sha256

  dotfiles_hermes_require_secret_tools
  manifest_path="$(dotfiles_hermes_bootstrap_manifest_path "$compose_file")" ||
    dotfiles_die "Hermes bootstrap manifest could not be located."
  manifest_sha256="$(dotfiles_hermes_bootstrap_manifest_sha256 "$manifest_path")" ||
    dotfiles_die "Hermes bootstrap manifest could not be hashed."
  set -o pipefail
  if ! compact_plan="$("$docker_runner" compose -f "$compose_file" run --rm --no-deps -T hermes-bootstrap secret-plan | dotfiles_hermes_validate_secret_plan "$(dotfiles_hermes_service_account_account)" "$manifest_sha256")"; then
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
    dotfiles_hermes_run_with_service_account_cache \
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
  port="${HERMES_DASHBOARD_PORT:-9119}"

  [[ $attempts =~ ^[1-9][0-9]*$ ]] || attempts=30
  [[ $delay_seconds =~ ^[0-9]+$ ]] || delay_seconds=2
  [[ $timeout_seconds =~ ^[1-9][0-9]*$ ]] || timeout_seconds=2
  # Desktop connects to the authenticated serve/dashboard backend, not the
  # gateway's OpenAI-compatible api_server adapter. The latter may be healthy
  # inside the Compose network while Docker Desktop's host-port forwarding is
  # still unavailable, so it is not a valid readiness signal for Desktop.
  url="http://127.0.0.1:${port}/api/health"

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if curl --fail --silent --show-error --max-time "$timeout_seconds" "$url" >/dev/null 2>&1; then
      return 0
    fi
    if ((attempt < attempts)); then
      sleep "$delay_seconds"
    fi
  done

  printf 'Hermes Desktop backend did not become ready after %s attempts.\n' "$attempts" >&2
  return 1
}

dotfiles_hermes_converge_gateways() {
  local docker_runner="$1"
  local compose_file="$2"

  "$docker_runner" compose -f "$compose_file" exec -T hermes \
    /usr/local/bin/hermes-gateway-converge
}

dotfiles_hermes_show_compose_diagnostics() {
  local docker_runner="$1"
  local compose_file="$2"

  "$docker_runner" compose -f "$compose_file" ps --all >&2 || true
}

dotfiles_hermes_prune_dangling_images() {
  local docker_runner="$1"

  "$docker_runner" image prune --force
}

dotfiles_hermes_runtime_exists() {
  local docker_runner="$1"
  local compose_file="$2"
  local services
  local service

  if services="$("$docker_runner" compose -f "$compose_file" ps --all --services hermes)"; then
    while IFS= read -r service; do
      [[ $service == hermes ]] && return 0
    done <<<"$services"
    return 1
  fi

  return 2
}

dotfiles_hermes_recover_stack_after_failure() {
  local docker_runner="$1"
  local compose_file="$2"

  if "$docker_runner" compose -f "$compose_file" start; then
    dotfiles_hermes_wait_for_api
  else
    return 1
  fi
}

dotfiles_hermes_start_stack() {
  local docker_runner="$1"
  local compose_file="$2"
  local status
  local runtime_existed=0

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
  if "$docker_runner" compose -f "$compose_file" build --pull hermes hermes-bootstrap chromium xapi-mcp; then
    :
  else
    status=$?
    dotfiles_hermes_show_compose_diagnostics "$docker_runner" "$compose_file"
    return "$status"
  fi
  if dotfiles_hermes_runtime_exists "$docker_runner" "$compose_file"; then
    runtime_existed=1
  else
    status=$?
    case "$status" in
    1) ;;
    *)
      dotfiles_hermes_show_compose_diagnostics "$docker_runner" "$compose_file"
      return "$status"
      ;;
    esac
  fi
  if "$docker_runner" compose -f "$compose_file" stop hermes; then
    :
  else
    status=$?
    dotfiles_hermes_show_compose_diagnostics "$docker_runner" "$compose_file"
    return "$status"
  fi
  if dotfiles_hermes_initialize_storage_volume "$docker_runner"; then
    :
  else
    status=$?
    if ((runtime_existed)) && dotfiles_hermes_recover_stack_after_failure "$docker_runner" "$compose_file"; then
      :
    else
      dotfiles_hermes_show_compose_diagnostics "$docker_runner" "$compose_file"
    fi
    return "$status"
  fi
  if dotfiles_hermes_run_bootstrap "$docker_runner" "$compose_file"; then
    :
  else
    status=$?
    if ((runtime_existed)) && dotfiles_hermes_recover_stack_after_failure "$docker_runner" "$compose_file"; then
      :
    else
      dotfiles_hermes_show_compose_diagnostics "$docker_runner" "$compose_file"
    fi
    return "$status"
  fi
  if dotfiles_hermes_ensure_xapi_auth "$docker_runner" "$compose_file"; then
    :
  else
    status=$?
    if ((runtime_existed)) && dotfiles_hermes_recover_stack_after_failure "$docker_runner" "$compose_file"; then
      :
    else
      dotfiles_hermes_show_compose_diagnostics "$docker_runner" "$compose_file"
    fi
    return "$status"
  fi
  if dotfiles_hermes_with_xapi_credentials_and_cache "$docker_runner" compose -f "$compose_file" up -d --force-recreate \
    hermes chromium browser-mcp xapi-mcp; then
    :
  else
    status=$?
    if ((runtime_existed)) && dotfiles_hermes_recover_stack_after_failure "$docker_runner" "$compose_file"; then
      :
    else
      dotfiles_hermes_show_compose_diagnostics "$docker_runner" "$compose_file"
    fi
    return "$status"
  fi
  if dotfiles_hermes_wait_for_api; then
    if dotfiles_hermes_converge_gateways "$docker_runner" "$compose_file"; then
      if ! dotfiles_hermes_prune_dangling_images "$docker_runner"; then
        printf '%s\n' 'Warning: unable to remove dangling Docker images.' >&2
      fi
    else
      status=$?
      dotfiles_hermes_show_compose_diagnostics "$docker_runner" "$compose_file"
      return "$status"
    fi
  else
    status=$?
    dotfiles_hermes_show_compose_diagnostics "$docker_runner" "$compose_file"
    return "$status"
  fi
}
