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
  local data_dir browser_data_dir
  data_dir="$(dotfiles_hermes_data_dir)"
  browser_data_dir="$(dotfiles_hermes_browser_data_dir)"

  mkdir -p "$data_dir" "$data_dir/.xurl" "$browser_data_dir"
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

dotfiles_hermes_validate_secret_plan() {
  jq -Ssce '
    if length == 1 and (.[0] | type == "object") then .[0] else false end
    |
    . as $plan | (
    def nonblank_string:
      type == "string" and test("[^[:space:]]") and test("^[^[:cntrl:]]+$");
    def field:
      type == "object"
      and (keys | sort == ["canonical_name", "labels"])
      and (.canonical_name | nonblank_string)
      and (.labels | type == "array" and length > 0 and all(.[]; nonblank_string));
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
    and (.items | type == "array" and length == 7)
    and ([.items[] | {key, account, vault, item}] == [
      {"key":"dashboard","account":"my.1password.com","vault":"openclaw","item":"Hermes Agent Dashboard"},
      {"key":"github","account":"my.1password.com","vault":"openclaw","item":"GitHubUsedOpenClawPAT"},
      {"key":"slack_default","account":"my.1password.com","vault":"openclaw","item":"SlackBot-OpenClaw"},
      {"key":"slack_rick","account":"my.1password.com","vault":"openclaw","item":"SlackBot-Rick"},
      {"key":"slack_hoffman","account":"my.1password.com","vault":"openclaw","item":"SlackBot-Hoffman"},
      {"key":"slack_risarisa","account":"my.1password.com","vault":"openclaw","item":"SlackBot-Risarisa"},
      {"key":"slack_nancy","account":"my.1password.com","vault":"openclaw","item":"SlackBot-Nancy"}
    ])
    and ([.items[].key] | unique | length == 7)
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
  if "$docker_runner" compose -f "$compose_file" up -d --force-recreate; then
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
