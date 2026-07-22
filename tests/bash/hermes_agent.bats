#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	TEST_HOME="$BATS_TEST_TMPDIR/home"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"
	mkdir -p "$TEST_HOME" "$STUB_BIN"
	: >"$COMMAND_LOG"

	export REPO_ROOT HOME="$TEST_HOME" PATH="$STUB_BIN:/usr/bin:/bin"
	export COMMAND_LOG
	export DOTFILES_HERMES_AGENT_1PASSWORD_ENABLED=0
	export DOTFILES_HERMES_AGENT_SLACK_1PASSWORD_ENABLED=0

	write_stub docker '
printf "docker %s\n" "$*" >>"$COMMAND_LOG"
if [ "${1:-}" = "run" ]; then
	printf "generated-password\nscrypt\$hash\ngenerated-secret\n"
fi
'
}

write_stub() {
	local name="$1"
	local body="$2"
	cat >"$STUB_BIN/$name" <<EOF
#!/usr/bin/env bash
set -euo pipefail
$body
EOF
	chmod +x "$STUB_BIN/$name"
}

run_hermes_auth_helper() {
	run bash -c '
set -euo pipefail
. "$REPO_ROOT/scripts/sh/install-common.sh"
. "$REPO_ROOT/scripts/sh/hermes-agent.sh"
dotfiles_hermes_ensure_dashboard_auth docker
'
}

run_hermes_config_helper() {
	run bash -c '
set -euo pipefail
. "$REPO_ROOT/scripts/sh/install-common.sh"
. "$REPO_ROOT/scripts/sh/hermes-agent.sh"
dotfiles_hermes_ensure_runtime_configuration
'
}

run_hermes_slack_helper() {
	run bash -c '
set -euo pipefail
. "$REPO_ROOT/scripts/sh/install-common.sh"
. "$REPO_ROOT/scripts/sh/hermes-agent.sh"
dotfiles_hermes_ensure_slack_environment
'
}

write_slack_jq_stub() {
	write_stub jq '
names=""
while [ "$#" -gt 0 ]; do
	if [ "${1:-}" = "--arg" ] && [ "${2:-}" = "names" ]; then
		names="${3:-}"
		shift 3
		continue
	fi
	shift
done
input="$(cat)"
case "$names" in
	*bot_token*) printf "%s\n" "$input" | sed -n "s/.*\"value\"[[:space:]]*:[[:space:]]*\"\(xoxb[^\"]*\)\".*/\1/p" | head -n 1 ;;
	*app_level_token*) printf "%s\n" "$input" | sed -n "s/.*\"value\"[[:space:]]*:[[:space:]]*\"\(xapp[^\"]*\)\".*/\1/p" | head -n 1 ;;
	*SLACK_ALLOWED_USERS*) printf "%s\n" "$input" | sed -n "s/.*\"value\"[[:space:]]*:[[:space:]]*\"\(U[^\"]*\)\".*/\1/p" | head -n 1 ;;
	*) exit 1 ;;
esac
'
}

@test "generates dashboard auth when Hermes env has no credentials" {
	run_hermes_auth_helper

	[ "$status" -eq 0 ]
	env_path="$TEST_HOME/.hermes/.env"
	password_path="$TEST_HOME/.hermes/dashboard-basic-auth-password.txt"
	[ -f "$env_path" ]
	[ -f "$password_path" ]
	grep -q '^HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin$' "$env_path"
	grep -q '^HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH=scrypt\$hash$' "$env_path"
	grep -q '^HERMES_DASHBOARD_BASIC_AUTH_SECRET=generated-secret$' "$env_path"
	! grep -q '^HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=' "$env_path"
	grep -q '^password=generated-password$' "$password_path"
	grep -q '^docker run --rm --entrypoint /opt/hermes/.venv/bin/python' "$COMMAND_LOG"
}

@test "preserves existing dashboard auth without regenerating credentials" {
	mkdir -p "$TEST_HOME/.hermes"
	cat >"$TEST_HOME/.hermes/.env" <<'EOF'
OTHER=value

HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin
HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH=existing-hash
HERMES_DASHBOARD_BASIC_AUTH_SECRET=existing-secret
EOF

	run_hermes_auth_helper

	[ "$status" -eq 0 ]
	grep -q '^OTHER=value$' "$TEST_HOME/.hermes/.env"
	grep -q '^HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH=existing-hash$' "$TEST_HOME/.hermes/.env"
	grep -q '^HERMES_DASHBOARD_BASIC_AUTH_SECRET=existing-secret$' "$TEST_HOME/.hermes/.env"
	[ ! -e "$TEST_HOME/.hermes/dashboard-basic-auth-password.txt" ]
	! grep -q '^docker run ' "$COMMAND_LOG"
}

@test "syncs root dashboard auth into existing managed profile env files" {
	mkdir -p "$TEST_HOME/.hermes/profiles/rick"
	cat >"$TEST_HOME/.hermes/profiles/rick/.env" <<'EOF'
PROFILE_ONLY=value
HERMES_DASHBOARD_BASIC_AUTH_USERNAME=stale
HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH=stale-hash
HERMES_DASHBOARD_BASIC_AUTH_SECRET=stale-secret
EOF

	run_hermes_auth_helper

	[ "$status" -eq 0 ]
	profile_env="$TEST_HOME/.hermes/profiles/rick/.env"
	grep -q '^PROFILE_ONLY=value$' "$profile_env"
	grep -q '^HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin$' "$profile_env"
	grep -q '^HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH=scrypt\$hash$' "$profile_env"
	grep -q '^HERMES_DASHBOARD_BASIC_AUTH_SECRET=generated-secret$' "$profile_env"
	! grep -q 'stale' "$profile_env"
}

@test "configures model and Slack mention policy while preserving other settings" {
	mkdir -p "$TEST_HOME/.hermes"
	cat >"$TEST_HOME/.hermes/config.yaml" <<'EOF'
model:
  provider: auto
  default: stale-model
terminal:
  timeout: 180
slack:
  allow_bots: none
  allowed_channels: C04AHA0CE4W
agent:
  max_turns: 60
EOF

	run_hermes_config_helper

	[ "$status" -eq 0 ]
	config_path="$TEST_HOME/.hermes/config.yaml"
	grep -q '^model:$' "$config_path"
	grep -q '^  provider: openai-codex$' "$config_path"
	grep -q '^  default: gpt-5\.6-luna$' "$config_path"
	grep -q '^  reasoning_effort: high$' "$config_path"
	grep -q '^slack:$' "$config_path"
	grep -q '^  require_mention: true$' "$config_path"
	grep -q '^  strict_mention: false$' "$config_path"
	grep -q '^  allow_bots: mentions$' "$config_path"
	grep -q '^  allowed_channels: C04AHA0CE4W$' "$config_path"
	grep -q '^terminal:$' "$config_path"
	grep -q '^agent:$' "$config_path"
	! grep -q 'stale-model\|allow_bots: none' "$config_path"
}

@test "configures the requested model and effort for existing Hermes profiles" {
	mkdir -p "$TEST_HOME/.hermes/profiles/nancy"
	cat >"$TEST_HOME/.hermes/profiles/nancy/config.yaml" <<'EOF'
model:
  provider: auto
  default: stale-model
agent:
  max_turns: 60
EOF

	run_hermes_config_helper

	[ "$status" -eq 0 ]
	for config_path in "$TEST_HOME/.hermes/config.yaml" "$TEST_HOME/.hermes/profiles/nancy/config.yaml"; do
		grep -q '^  default: gpt-5\.6-luna$' "$config_path"
		grep -q '^  reasoning_effort: high$' "$config_path"
	done
	grep -q '^  max_turns: 60$' "$TEST_HOME/.hermes/profiles/nancy/config.yaml"
}

@test "configures Slack environment from the 1Password item" {
	export DOTFILES_HERMES_AGENT_SLACK_1PASSWORD_ENABLED=1
	write_stub op '
printf "op %s\n" "$*" >>"$COMMAND_LOG"
if [ "${1:-}" = "item" ] && [ "${2:-}" = "get" ] && [ "${3:-}" = "SlackBot-OpenClaw" ]; then
	cat <<'"'"'JSON'"'"'
{
  "fields": [
    {"id": "bot_token", "label": "bot_token", "value": "xoxb-test-bot-token"},
    {"id": "app_level_token", "label": "app_level_token", "value": "xapp-test-app-token"},
    {"id": "SLACK_ALLOWED_USERS", "label": "SLACK_ALLOWED_USERS", "value": "U04BDJU87KJ"}
  ]
}
JSON
	exit 0
fi
exit 1
'
	write_slack_jq_stub

	run_hermes_slack_helper

	[ "$status" -eq 0 ]
	env_path="$TEST_HOME/.hermes/.env"
	grep -q '^SLACK_BOT_TOKEN=xoxb-test-bot-token$' "$env_path"
	grep -q '^SLACK_APP_TOKEN=xapp-test-app-token$' "$env_path"
	grep -q '^SLACK_ALLOWED_USERS=U04BDJU87KJ$' "$env_path"
	grep -q 'SlackBot-OpenClaw' "$COMMAND_LOG"
	grep -q -- '--vault openclaw' "$COMMAND_LOG"
}

@test "configures managed profile Slack environment from dedicated 1Password items" {
	export DOTFILES_HERMES_AGENT_SLACK_1PASSWORD_ENABLED=0
	export DOTFILES_HERMES_AGENT_RISARISA_SLACK_1PASSWORD_ENABLED=1
	mkdir -p "$TEST_HOME/.hermes/profiles/risarisa"
	cat >"$TEST_HOME/.hermes/.env" <<'EOF'
SLACK_BOT_TOKEN=xoxb-root
SLACK_APP_TOKEN=xapp-root
SLACK_ALLOWED_USERS=UROOT
EOF
	cat >"$TEST_HOME/.hermes/profiles/risarisa/.env" <<'EOF'
OTHER=value
SLACK_BOT_TOKEN=xoxb-cloned-default
SLACK_APP_TOKEN=xapp-cloned-default
SLACK_ALLOWED_USERS=UDEFAULT
EOF
	write_stub op '
printf "op %s\n" "$*" >>"$COMMAND_LOG"
if [ "${1:-}" = "item" ] && [ "${2:-}" = "get" ] && [ "${3:-}" = "SlackBot-Risarisa" ]; then
	cat <<JSON
{
  "fields": [
    {"id": "bot_token", "label": "bot_token", "value": "xoxb-risarisa-bot-token"},
    {"id": "app_level_token", "label": "app_level_token", "value": "xapp-risarisa-app-token"},
    {"id": "SLACK_ALLOWED_USERS", "label": "SLACK_ALLOWED_USERS", "value": "URISARISA"}
  ]
}
JSON
	exit 0
fi
exit 1
'
	write_slack_jq_stub

	run_hermes_slack_helper

	[ "$status" -eq 0 ]
	profile_env="$TEST_HOME/.hermes/profiles/risarisa/.env"
	grep -q '^OTHER=value$' "$profile_env"
	grep -q '^SLACK_BOT_TOKEN=xoxb-risarisa-bot-token$' "$profile_env"
	grep -q '^SLACK_APP_TOKEN=xapp-risarisa-app-token$' "$profile_env"
	grep -q '^SLACK_ALLOWED_USERS=URISARISA$' "$profile_env"
	! grep -q 'xoxb-cloned-default' "$profile_env"
	grep -q 'SlackBot-Risarisa' "$COMMAND_LOG"
}
