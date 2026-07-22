#!/usr/bin/env bash

DOTFILES_HERMES_DASHBOARD_AUTH_IMAGE="${DOTFILES_HERMES_DASHBOARD_AUTH_IMAGE:-local/hermes-agent-gh:latest}"

dotfiles_is_falsey() {
  case "${1:-}" in
  0 | false | FALSE | False | no | NO | No | off | OFF | Off) return 0 ;;
  *) return 1 ;;
  esac
}

dotfiles_is_truthy() {
  case "${1:-}" in
  1 | true | TRUE | True | yes | YES | Yes | on | ON | On) return 0 ;;
  *) return 1 ;;
  esac
}

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

dotfiles_hermes_env_value() {
  local env_path="$1"
  local key="$2"
  [[ -f $env_path ]] || return 0

  awk -v key="$key" '
		$0 ~ "^[[:space:]]*(export[[:space:]]+)?" key "[[:space:]]*=" {
			value = $0
			sub("^[[:space:]]*(export[[:space:]]+)?" key "[[:space:]]*=[[:space:]]*", "", value)
			print value
		}
	' "$env_path" | tail -n 1
}

dotfiles_hermes_has_dashboard_auth() {
  local env_path="$1"
  local key value
  for key in \
    HERMES_DASHBOARD_BASIC_AUTH_USERNAME \
    HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH \
    HERMES_DASHBOARD_BASIC_AUTH_SECRET; do
    value="$(dotfiles_hermes_env_value "$env_path" "$key")"
    [[ -n $value ]] || return 1
  done
  return 0
}

dotfiles_hermes_output_line() {
  local line_number="$1"
  awk -v wanted="$line_number" '
		NF {
			count += 1
			if (count == wanted) {
				print
				exit
			}
		}
	'
}

dotfiles_hermes_write_dashboard_auth() {
  local env_path="$1"
  local username="$2"
  local password_hash="$3"
  local secret="$4"
  local env_dir tmp

  env_dir="$(dirname "$env_path")"
  mkdir -p "$env_dir"
  tmp="$(mktemp "$env_path.tmp.XXXXXX")"

  if [[ -f $env_path ]]; then
    awk '
			$0 !~ /^[[:space:]]*(export[[:space:]]+)?HERMES_DASHBOARD_BASIC_AUTH_(USERNAME|PASSWORD|PASSWORD_HASH|SECRET)[[:space:]]*=/
		' "$env_path" >"$tmp"
  else
    : >"$tmp"
  fi

  if [[ -s $tmp ]] && [[ -n $(tail -n 1 "$tmp") ]]; then
    printf '\n' >>"$tmp"
  fi
  printf 'HERMES_DASHBOARD_BASIC_AUTH_USERNAME=%s\n' "$username" >>"$tmp"
  printf 'HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH=%s\n' "$password_hash" >>"$tmp"
  printf 'HERMES_DASHBOARD_BASIC_AUTH_SECRET=%s\n' "$secret" >>"$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$env_path"
}

dotfiles_hermes_sync_dashboard_auth_to_profiles() {
  local data_dir="$1"
  local username="$2"
  local password_hash="$3"
  local secret="$4"
  local profiles_dir profile_dir

  if dotfiles_is_falsey "${DOTFILES_HERMES_SYNC_DASHBOARD_AUTH_TO_PROFILES:-true}"; then
    return
  fi

  profiles_dir="$data_dir/profiles"
  [[ -d $profiles_dir ]] || return 0
  for profile_dir in "$profiles_dir"/*; do
    [[ -d $profile_dir ]] || continue
    dotfiles_hermes_write_dashboard_auth "$profile_dir/.env" "$username" "$password_hash" "$secret"
  done
  return 0
}

dotfiles_hermes_has_slack_environment() {
  local env_path="$1"
  local key value
  for key in SLACK_BOT_TOKEN SLACK_APP_TOKEN SLACK_ALLOWED_USERS; do
    value="$(dotfiles_hermes_env_value "$env_path" "$key")"
    [[ -n $value ]] || return 1
  done
  return 0
}

dotfiles_hermes_write_slack_environment() {
  local env_path="$1"
  local bot_token="$2"
  local app_token="$3"
  local allowed_users="$4"
  local env_dir tmp

  env_dir="$(dirname "$env_path")"
  mkdir -p "$env_dir"
  tmp="$(mktemp "$env_path.tmp.XXXXXX")"

  if [[ -f $env_path ]]; then
    awk '
			$0 !~ /^[[:space:]]*(export[[:space:]]+)?SLACK_(BOT_TOKEN|APP_TOKEN|ALLOWED_USERS)[[:space:]]*=/
		' "$env_path" >"$tmp"
  else
    : >"$tmp"
  fi

  if [[ -s $tmp ]] && [[ -n $(tail -n 1 "$tmp") ]]; then
    printf '\n' >>"$tmp"
  fi
  printf 'SLACK_BOT_TOKEN=%s\n' "$bot_token" >>"$tmp"
  printf 'SLACK_APP_TOKEN=%s\n' "$app_token" >>"$tmp"
  printf 'SLACK_ALLOWED_USERS=%s\n' "$allowed_users" >>"$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$env_path"
}

dotfiles_hermes_env_or_default() {
  local name="$1"
  local default_value="$2"
  if [[ -n ${!name+x} ]]; then
    printf '%s\n' "${!name}"
  else
    printf '%s\n' "$default_value"
  fi
}

dotfiles_hermes_trim() {
  awk '{$1=$1; print}'
}

dotfiles_hermes_profile_key() {
  printf '%s\n' "$1" | tr '[:lower:]' '[:upper:]' | sed 's/[^A-Z0-9]/_/g'
}

dotfiles_hermes_profile_title() {
  local lower first rest

  lower="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  first="$(printf '%s' "$lower" | cut -c1 | tr '[:lower:]' '[:upper:]')"
  rest="$(printf '%s' "$lower" | cut -c2-)"
  printf '%s%s\n' "$first" "$rest"
}

dotfiles_hermes_onepassword_field() {
  local item_json="$1"
  local purpose="$2"
  local names="$3"

  printf '%s\n' "$item_json" | jq -r --arg purpose "$purpose" --arg names "$names" '
		($names | split("|") | map(ascii_downcase)) as $wanted_names |
		def norm: tostring | ascii_downcase;
		[
				.fields[]?
				| select(
					(($purpose != "") and ((.purpose // "") == $purpose) and (((.value // "") | tostring | length) > 0))
					or (((.id // "") | norm) as $id | ($wanted_names | index($id)))
					or (((.label // "") | norm) as $label | ($wanted_names | index($label)))
				)
			| (.value // empty)
		][0] // empty
		'
}

dotfiles_hermes_get_onepassword_slack_environment_for_item() {
  local enabled="$1"
  local required_value="$2"
  local account="$3"
  local vault="$4"
  local item="$5"
  local required item_json bot_token app_token allowed_users

  if dotfiles_is_falsey "$enabled"; then
    return 1
  fi

  required=1
  if dotfiles_is_falsey "$required_value"; then
    required=0
  fi

  if ! dotfiles_have op; then
    ((required == 0)) || dotfiles_die "1Password CLI (op) is required for Hermes Slack setup."
    dotfiles_log "1Password CLI is unavailable; skipping Hermes Slack setup."
    return 1
  fi
  if ! dotfiles_have jq; then
    ((required == 0)) || dotfiles_die "jq is required to read Hermes Slack credentials from 1Password."
    dotfiles_log "jq is unavailable; skipping Hermes Slack setup."
    return 1
  fi

  if ! item_json="$(op item get "$item" --account "$account" --vault "$vault" --format json 2>/dev/null)"; then
    ((required == 0)) || dotfiles_die "Unable to read Hermes Slack credentials from 1Password: $item"
    dotfiles_log "Hermes Slack credentials are unavailable in 1Password; skipping Slack setup: $item"
    return 1
  fi

  bot_token="$(dotfiles_hermes_onepassword_field "$item_json" "" 'SLACK_BOT_TOKEN|bot_token|bot token')"
  app_token="$(dotfiles_hermes_onepassword_field "$item_json" "" 'SLACK_APP_TOKEN|app_level_token|app token|app-level token')"
  allowed_users="$(dotfiles_hermes_onepassword_field "$item_json" "" 'SLACK_ALLOWED_USERS|allowed_users|allowed users|allowFrom|allow_from')"
  if [[ -z $bot_token || -z $app_token || -z $allowed_users ]]; then
    ((required == 0)) || dotfiles_die "1Password item is missing Hermes Slack token or allowed-user fields: $item"
    dotfiles_log "Hermes Slack 1Password item is incomplete; skipping Slack setup: $item"
    return 1
  fi

  DOTFILES_HERMES_SLACK_BOT_TOKEN="$bot_token"
  DOTFILES_HERMES_SLACK_APP_TOKEN="$app_token"
  DOTFILES_HERMES_SLACK_ALLOWED_USERS="$allowed_users"
  return 0
}

dotfiles_hermes_get_onepassword_slack_environment() {
  dotfiles_hermes_get_onepassword_slack_environment_for_item \
    "${DOTFILES_HERMES_AGENT_SLACK_1PASSWORD_ENABLED:-true}" \
    "${DOTFILES_HERMES_AGENT_REQUIRE_SLACK:-true}" \
    "${DOTFILES_HERMES_AGENT_SLACK_1PASSWORD_ACCOUNT:-my.1password.com}" \
    "${DOTFILES_HERMES_AGENT_SLACK_1PASSWORD_VAULT:-openclaw}" \
    "${DOTFILES_HERMES_AGENT_SLACK_1PASSWORD_ITEM:-SlackBot-OpenClaw}"
}

dotfiles_hermes_sync_slack_environment_to_profiles() {
  local data_dir="$1"
  local profiles_dir profile_names profile_name profile_dir profile_key profile_title
  local default_enabled enabled required account vault item
  local profile_names_array

  profiles_dir="$data_dir/profiles"
  [[ -d $profiles_dir ]] || return 0

  default_enabled="${DOTFILES_HERMES_AGENT_SLACK_1PASSWORD_ENABLED:-true}"
  profile_names="${DOTFILES_HERMES_AGENT_MANAGED_PROFILES:-rick,hoffman,risarisa}"
  IFS=, read -r -a profile_names_array <<<"$profile_names"
  for profile_name in "${profile_names_array[@]}"; do
    profile_name="$(printf '%s\n' "$profile_name" | dotfiles_hermes_trim)"
    [[ -n $profile_name ]] || continue

    profile_dir="$profiles_dir/$profile_name"
    [[ -d $profile_dir ]] || continue

    profile_key="$(dotfiles_hermes_profile_key "$profile_name")"
    profile_title="$(dotfiles_hermes_profile_title "$profile_name")"
    enabled="$(dotfiles_hermes_env_or_default "DOTFILES_HERMES_AGENT_${profile_key}_SLACK_1PASSWORD_ENABLED" "$default_enabled")"
    required="$(dotfiles_hermes_env_or_default "DOTFILES_HERMES_AGENT_REQUIRE_${profile_key}_SLACK" "${DOTFILES_HERMES_AGENT_REQUIRE_SLACK:-true}")"
    account="$(dotfiles_hermes_env_or_default "DOTFILES_HERMES_AGENT_${profile_key}_SLACK_1PASSWORD_ACCOUNT" "${DOTFILES_HERMES_AGENT_SLACK_1PASSWORD_ACCOUNT:-my.1password.com}")"
    vault="$(dotfiles_hermes_env_or_default "DOTFILES_HERMES_AGENT_${profile_key}_SLACK_1PASSWORD_VAULT" "${DOTFILES_HERMES_AGENT_SLACK_1PASSWORD_VAULT:-openclaw}")"
    item="$(dotfiles_hermes_env_or_default "DOTFILES_HERMES_AGENT_${profile_key}_SLACK_1PASSWORD_ITEM" "SlackBot-$profile_title")"

    if dotfiles_hermes_get_onepassword_slack_environment_for_item "$enabled" "$required" "$account" "$vault" "$item"; then
      dotfiles_hermes_write_slack_environment \
        "$profile_dir/.env" \
        "$DOTFILES_HERMES_SLACK_BOT_TOKEN" \
        "$DOTFILES_HERMES_SLACK_APP_TOKEN" \
        "$DOTFILES_HERMES_SLACK_ALLOWED_USERS"
      dotfiles_log "Configured Hermes Slack environment for managed profile: $profile_name"
    elif dotfiles_hermes_has_slack_environment "$profile_dir/.env"; then
      dotfiles_log "Hermes Slack environment is already configured for managed profile: $profile_name"
    fi
  done
}

dotfiles_hermes_ensure_slack_environment() {
  local data_dir env_path

  dotfiles_hermes_prepare_runtime_home
  data_dir="$(dotfiles_hermes_data_dir)"
  env_path="$data_dir/.env"

  if dotfiles_hermes_has_slack_environment "$env_path"; then
    dotfiles_log "Hermes Slack environment is already configured."
    dotfiles_hermes_sync_slack_environment_to_profiles "$data_dir"
    return
  fi

  if dotfiles_hermes_get_onepassword_slack_environment; then
    dotfiles_hermes_write_slack_environment \
      "$env_path" \
      "$DOTFILES_HERMES_SLACK_BOT_TOKEN" \
      "$DOTFILES_HERMES_SLACK_APP_TOKEN" \
      "$DOTFILES_HERMES_SLACK_ALLOWED_USERS"
    dotfiles_log "Configured Hermes Slack environment from 1Password."
  fi

  dotfiles_hermes_sync_slack_environment_to_profiles "$data_dir"
}

dotfiles_hermes_remove_top_level_block() {
  local config_path="$1"
  local key="$2"

  if [[ ! -f $config_path ]]; then
    return
  fi

  awk -v key="$key" '
		function top_level(line) {
			return line ~ /^[^[:space:]#][^:]*:/
		}
		top_level($0) {
			if ($0 ~ "^" key ":[[:space:]]*($|#)") {
				skip = 1
				next
			}
			skip = 0
		}
		!skip { print }
	' "$config_path"
}

dotfiles_hermes_existing_slack_child_lines() {
  local config_path="$1"
  [[ -f $config_path ]] || return 0

  awk '
		function top_level(line) {
			return line ~ /^[^[:space:]#][^:]*:/
		}
		top_level($0) {
			in_slack = ($0 ~ /^slack:[[:space:]]*($|#)/)
			next
		}
		in_slack && $0 ~ /^  [A-Za-z0-9_-]+:[[:space:]]*/ {
			if ($0 !~ /^  (require_mention|strict_mention|allow_bots):[[:space:]]*/) {
				print
			}
		}
	' "$config_path"
}

dotfiles_hermes_existing_agent_child_lines() {
  local config_path="$1"
  [[ -f $config_path ]] || return 0

  awk '
		function top_level(line) {
			return line ~ /^[^[:space:]#][^:]*:/
		}
		top_level($0) {
			in_agent = ($0 ~ /^agent:[[:space:]]*($|#)/)
			next
		}
		in_agent && $0 ~ /^  [A-Za-z0-9_-]+:[[:space:]]*/ {
			if ($0 !~ /^  reasoning_effort:[[:space:]]*/) {
				print
			}
		}
	' "$config_path"
}

dotfiles_hermes_write_config_block() {
  local config_path="$1"
  local key="$2"
  local block="$3"
  local config_dir tmp

  config_dir="$(dirname "$config_path")"
  mkdir -p "$config_dir"
  tmp="$(mktemp "$config_path.tmp.XXXXXX")"
  dotfiles_hermes_remove_top_level_block "$config_path" "$key" >"$tmp"
  if [[ -s $tmp ]] && [[ -n $(tail -n 1 "$tmp") ]]; then
    printf '\n' >>"$tmp"
  fi
  printf '%s\n' "$block" >>"$tmp"
  mv "$tmp" "$config_path"
}

dotfiles_hermes_write_model_configuration() {
  local config_path="$1"
  local provider="$2"
  local model="$3"
  local effort="$4"
  local preserved block

  block="model:
  provider: $provider
  default: $model"
  dotfiles_hermes_write_config_block "$config_path" model "$block"

  preserved="$(dotfiles_hermes_existing_agent_child_lines "$config_path")"
  block="agent:
  reasoning_effort: $effort"
  if [[ -n $preserved ]]; then
    block="$block
$preserved"
  fi
  dotfiles_hermes_write_config_block "$config_path" agent "$block"
}

dotfiles_hermes_ensure_model_configuration() {
  local data_dir config_path profiles_dir profile_dir provider model effort

  if dotfiles_is_falsey "${DOTFILES_HERMES_AGENT_MODEL_CONFIG_ENABLED:-true}"; then
    return
  fi

  dotfiles_hermes_prepare_runtime_home
  data_dir="$(dotfiles_hermes_data_dir)"
  config_path="$data_dir/config.yaml"
  provider="${DOTFILES_HERMES_AGENT_MODEL_PROVIDER:-openai-codex}"
  model="${DOTFILES_HERMES_AGENT_MODEL_DEFAULT:-gpt-5.6-luna}"
  effort="${DOTFILES_HERMES_AGENT_REASONING_EFFORT:-high}"
  dotfiles_hermes_write_model_configuration "$config_path" "$provider" "$model" "$effort"

  profiles_dir="$data_dir/profiles"
  [[ -d $profiles_dir ]] || return 0
  for profile_dir in "$profiles_dir"/*; do
    [[ -d $profile_dir ]] || continue
    dotfiles_hermes_write_model_configuration "$profile_dir/config.yaml" "$provider" "$model" "$effort"
  done
}

dotfiles_hermes_ensure_slack_mention_configuration() {
  local data_dir config_path preserved block

  if dotfiles_is_falsey "${DOTFILES_HERMES_AGENT_SLACK_CONFIG_ENABLED:-true}"; then
    return
  fi

  dotfiles_hermes_prepare_runtime_home
  data_dir="$(dotfiles_hermes_data_dir)"
  config_path="$data_dir/config.yaml"
  preserved="$(dotfiles_hermes_existing_slack_child_lines "$config_path")"
  block="slack:
  require_mention: true
  strict_mention: false
  allow_bots: mentions"
  if [[ -n $preserved ]]; then
    block="$block
$preserved"
  fi
  dotfiles_hermes_write_config_block "$config_path" slack "$block"
}

dotfiles_hermes_ensure_runtime_configuration() {
  dotfiles_hermes_ensure_model_configuration
  dotfiles_hermes_ensure_slack_mention_configuration
}

dotfiles_hermes_set_onepassword_dashboard_credentials() {
  local docker_runner="$1"
  local required account vault item item_json username password output

  if dotfiles_is_falsey "${DOTFILES_HERMES_AGENT_1PASSWORD_ENABLED:-true}"; then
    return 1
  fi

  required=0
  if dotfiles_is_truthy "${DOTFILES_HERMES_AGENT_REQUIRE_1PASSWORD:-false}"; then
    required=1
  fi

  if ! dotfiles_have op; then
    ((required == 0)) || dotfiles_die "1Password CLI (op) is required for Hermes dashboard credential setup."
    dotfiles_log "1Password CLI is unavailable; generating local Hermes dashboard credentials."
    return 1
  fi
  if ! dotfiles_have jq; then
    ((required == 0)) || dotfiles_die "jq is required to read Hermes dashboard credentials from 1Password."
    dotfiles_log "jq is unavailable; generating local Hermes dashboard credentials."
    return 1
  fi

  account="${DOTFILES_HERMES_AGENT_1PASSWORD_ACCOUNT:-my.1password.com}"
  vault="${DOTFILES_HERMES_AGENT_1PASSWORD_VAULT:-openclaw}"
  item="${DOTFILES_HERMES_AGENT_1PASSWORD_ITEM:-Hermes Agent Dashboard}"
  if ! item_json="$(op item get "$item" --account "$account" --vault "$vault" --format json 2>/dev/null)"; then
    ((required == 0)) || dotfiles_die "Unable to read Hermes dashboard credential from 1Password."
    dotfiles_log "1Password Hermes dashboard credential is unavailable; generating local credentials."
    return 1
  fi

  username="$(dotfiles_hermes_onepassword_field "$item_json" USERNAME 'username|user name')"
  password="$(dotfiles_hermes_onepassword_field "$item_json" PASSWORD 'password')"
  if [[ -z $username || -z $password ]]; then
    ((required == 0)) || dotfiles_die "1Password item is missing Hermes dashboard username/password fields."
    dotfiles_log "1Password Hermes dashboard item is incomplete; generating local credentials."
    return 1
  fi

  output="$(dotfiles_hermes_hash_dashboard_password "$docker_runner" "$password")"
  DOTFILES_HERMES_DASHBOARD_USERNAME="$username"
  DOTFILES_HERMES_DASHBOARD_PASSWORD=""
  DOTFILES_HERMES_DASHBOARD_PASSWORD_HASH="$(printf '%s\n' "$output" | dotfiles_hermes_output_line 1)"
  DOTFILES_HERMES_DASHBOARD_SECRET="$(printf '%s\n' "$output" | dotfiles_hermes_output_line 2)"
  [[ -n $DOTFILES_HERMES_DASHBOARD_PASSWORD_HASH && -n $DOTFILES_HERMES_DASHBOARD_SECRET ]] ||
    dotfiles_die "Hermes dashboard password hash generation returned incomplete output."
  return 0
}

dotfiles_hermes_hash_dashboard_password() {
  local docker_runner="$1"
  local password="$2"
  local temp_dir password_path output python

  temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/hermes-dashboard-auth.XXXXXX")"
  password_path="$temp_dir/password"
  printf '%s' "$password" >"$password_path"
  chmod 600 "$password_path"
  python='from pathlib import Path
import secrets
from plugins.dashboard_auth.basic import hash_password

password = Path("/run/secrets/hermes_dashboard_password").read_text(encoding="utf-8")
print(hash_password(password))
print(secrets.token_urlsafe(48))
'
  if ! output="$("$docker_runner" run \
    --rm \
    --mount "type=bind,source=$password_path,target=/run/secrets/hermes_dashboard_password,readonly" \
    --entrypoint /opt/hermes/.venv/bin/python \
    -w /opt/hermes \
    "$DOTFILES_HERMES_DASHBOARD_AUTH_IMAGE" \
    -c "$python")"; then
    rm -rf "$temp_dir"
    dotfiles_die "Hermes dashboard password hash generation failed."
  fi
  rm -rf "$temp_dir"
  printf '%s\n' "$output"
}

dotfiles_hermes_set_generated_dashboard_credentials() {
  local docker_runner="$1"
  local output python

  python='import secrets
from plugins.dashboard_auth.basic import hash_password

password = secrets.token_urlsafe(32)
print(password)
print(hash_password(password))
print(secrets.token_urlsafe(48))
'
  if ! output="$("$docker_runner" run \
    --rm \
    --entrypoint /opt/hermes/.venv/bin/python \
    -w /opt/hermes \
    "$DOTFILES_HERMES_DASHBOARD_AUTH_IMAGE" \
    -c "$python")"; then
    dotfiles_die "Hermes dashboard credential generation failed."
  fi

  DOTFILES_HERMES_DASHBOARD_USERNAME="admin"
  DOTFILES_HERMES_DASHBOARD_PASSWORD="$(printf '%s\n' "$output" | dotfiles_hermes_output_line 1)"
  DOTFILES_HERMES_DASHBOARD_PASSWORD_HASH="$(printf '%s\n' "$output" | dotfiles_hermes_output_line 2)"
  DOTFILES_HERMES_DASHBOARD_SECRET="$(printf '%s\n' "$output" | dotfiles_hermes_output_line 3)"
  [[ -n $DOTFILES_HERMES_DASHBOARD_PASSWORD && -n $DOTFILES_HERMES_DASHBOARD_PASSWORD_HASH && -n $DOTFILES_HERMES_DASHBOARD_SECRET ]] ||
    dotfiles_die "Hermes dashboard credential generation returned incomplete output."
}

dotfiles_hermes_write_generated_password_info() {
  local info_file_path="$1"
  local username="$2"
  local password="$3"
  local info_dir

  info_dir="$(dirname "$info_file_path")"
  mkdir -p "$info_dir"
  cat >"$info_file_path" <<EOF
url=http://127.0.0.1:${HERMES_DASHBOARD_PORT:-9119}
username=$username
password=$password
EOF
  chmod 600 "$info_file_path"
}

dotfiles_hermes_ensure_dashboard_auth() {
  local docker_runner="${1:-docker}"
  local data_dir env_path info_file_path username password_hash secret

  if dotfiles_is_falsey "${DOTFILES_HERMES_DASHBOARD_AUTH_ENABLED:-true}"; then
    return
  fi

  dotfiles_hermes_prepare_runtime_home
  data_dir="$(dotfiles_hermes_data_dir)"
  env_path="$data_dir/.env"
  info_file_path="$data_dir/dashboard-basic-auth-password.txt"

  if dotfiles_hermes_has_dashboard_auth "$env_path"; then
    username="$(dotfiles_hermes_env_value "$env_path" HERMES_DASHBOARD_BASIC_AUTH_USERNAME)"
    password_hash="$(dotfiles_hermes_env_value "$env_path" HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH)"
    secret="$(dotfiles_hermes_env_value "$env_path" HERMES_DASHBOARD_BASIC_AUTH_SECRET)"
    dotfiles_hermes_sync_dashboard_auth_to_profiles "$data_dir" "$username" "$password_hash" "$secret"
    dotfiles_log "Hermes dashboard Basic Auth is already configured."
    return
  fi

  if dotfiles_hermes_set_onepassword_dashboard_credentials "$docker_runner"; then
    dotfiles_hermes_write_dashboard_auth \
      "$env_path" \
      "$DOTFILES_HERMES_DASHBOARD_USERNAME" \
      "$DOTFILES_HERMES_DASHBOARD_PASSWORD_HASH" \
      "$DOTFILES_HERMES_DASHBOARD_SECRET"
    rm -f "$info_file_path"
    dotfiles_log "Configured Hermes dashboard Basic Auth from 1Password."
  else
    dotfiles_hermes_set_generated_dashboard_credentials "$docker_runner"
    dotfiles_hermes_write_dashboard_auth \
      "$env_path" \
      "$DOTFILES_HERMES_DASHBOARD_USERNAME" \
      "$DOTFILES_HERMES_DASHBOARD_PASSWORD_HASH" \
      "$DOTFILES_HERMES_DASHBOARD_SECRET"
    dotfiles_hermes_write_generated_password_info \
      "$info_file_path" \
      "$DOTFILES_HERMES_DASHBOARD_USERNAME" \
      "$DOTFILES_HERMES_DASHBOARD_PASSWORD"
    dotfiles_log "Generated Hermes dashboard Basic Auth: $info_file_path"
  fi

  dotfiles_hermes_sync_dashboard_auth_to_profiles \
    "$data_dir" \
    "$DOTFILES_HERMES_DASHBOARD_USERNAME" \
    "$DOTFILES_HERMES_DASHBOARD_PASSWORD_HASH" \
    "$DOTFILES_HERMES_DASHBOARD_SECRET"
}
