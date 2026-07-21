#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	TEST_HOME="$BATS_TEST_TMPDIR/home"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"
	PAYLOAD_CAPTURE="$BATS_TEST_TMPDIR/payload.ndjson"
	COMPOSE_FILE="$BATS_TEST_TMPDIR/compose file.yml"
	REAL_JQ="$(command -v jq)"
	SECRET_MARKER="adapter-secret-marker"
	mkdir -p "$TEST_HOME" "$STUB_BIN"
	: >"$COMMAND_LOG"
	: >"$PAYLOAD_CAPTURE"
	: >"$COMPOSE_FILE"

	export REPO_ROOT HOME="$TEST_HOME" PATH="$STUB_BIN:/usr/bin:/bin"
	export COMMAND_LOG PAYLOAD_CAPTURE COMPOSE_FILE REAL_JQ SECRET_MARKER
	export PLAN_JSON="$(valid_secret_plan)"
	export OP_ITEM_JSON='{"id":"item-id","fields":[{"label":"credential","value":"adapter-secret-marker"}]}'
	export BOOTSTRAP_STATUS=0
	export OP_FAIL_ITEM=""

	write_stub jq '
exec "$REAL_JQ" "$@"
'
	write_stub op '
printf "op" >>"$COMMAND_LOG"
printf " <%s>" "$@" >>"$COMMAND_LOG"
printf "\n" >>"$COMMAND_LOG"
if [ "${3:-}" = "$OP_FAIL_ITEM" ]; then
	exit 17
fi
printf "%s\n" "$OP_ITEM_JSON"
'
	write_stub docker '
printf "docker" >>"$COMMAND_LOG"
printf " <%s>" "$@" >>"$COMMAND_LOG"
printf "\n" >>"$COMMAND_LOG"
if [ "${1:-}" != "compose" ]; then
	exit 1
fi
case " $* " in
  *" secret-plan "*) printf "%s\n" "$PLAN_JSON" ;;
  *" apply "*) cat >"$PAYLOAD_CAPTURE"; exit "$BOOTSTRAP_STATUS" ;;
esac
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

valid_secret_plan() {
	cat <<'JSON'
{"schema_version":1,"items":[{"key":"dashboard","account":"my.1password.com","vault":"openclaw","item":"Hermes Agent Dashboard","fields":[{"canonical_name":"username","labels":["username"]},{"canonical_name":"password","labels":["password"]}]},{"key":"github","account":"my.1password.com","vault":"openclaw","item":"GitHubUsedOpenClawPAT","fields":[{"canonical_name":"credential","labels":["credential"]}]},{"key":"slack_default","account":"my.1password.com","vault":"openclaw","item":"SlackBot-OpenClaw","fields":[{"canonical_name":"bot_token","labels":["SLACK_BOT_TOKEN"]}]},{"key":"slack_rick","account":"my.1password.com","vault":"openclaw","item":"SlackBot-Rick","fields":[{"canonical_name":"bot_token","labels":["SLACK_BOT_TOKEN"]}]},{"key":"slack_hoffman","account":"my.1password.com","vault":"openclaw","item":"SlackBot-Hoffman","fields":[{"canonical_name":"bot_token","labels":["SLACK_BOT_TOKEN"]}]},{"key":"slack_risarisa","account":"my.1password.com","vault":"openclaw","item":"SlackBot-Risarisa","fields":[{"canonical_name":"bot_token","labels":["SLACK_BOT_TOKEN"]}]}]}
JSON
}

run_start_stack() {
	run bash -c '
set -euo pipefail
. "$REPO_ROOT/scripts/sh/install-common.sh"
. "$REPO_ROOT/scripts/sh/hermes-agent.sh"
dotfiles_hermes_start_stack docker "$COMPOSE_FILE"
'
}

run_start_stack_with_function_runner() {
	run bash -c '
set -euo pipefail
. "$REPO_ROOT/scripts/sh/install-common.sh"
. "$REPO_ROOT/scripts/sh/hermes-agent.sh"
docker_command() {
  printf "runner" >>"$COMMAND_LOG"
  printf " <%s>" "$@" >>"$COMMAND_LOG"
  printf "\n" >>"$COMMAND_LOG"
  docker "$@"
}
dotfiles_hermes_start_stack docker_command "$COMPOSE_FILE"
'
}

assert_log_order() {
	local previous=0
	local pattern line
	for pattern in "$@"; do
		line="$(grep -n -m 1 -- "$pattern" "$COMMAND_LOG" | cut -d: -f1)"
		[ -n "$line" ]
		[ "$line" -gt "$previous" ]
		previous="$line"
	done
}

assert_plan_rejected_before_secret_lookup() {
	: >"$COMMAND_LOG"
	run_start_stack
	[ "$status" -ne 0 ]
	[[ "$output" == *"secret plan is invalid"* ]]
	! grep -q '^op' "$COMMAND_LOG"
	! grep -q '<apply>' "$COMMAND_LOG"
}

@test "preserves Hermes data and browser directory helpers" {
	export HERMES_DATA_DIR="$TEST_HOME/custom-data"
	export HERMES_BROWSER_DATA_DIR="$TEST_HOME/custom-browser"

	run bash -c '
set -euo pipefail
. "$REPO_ROOT/scripts/sh/install-common.sh"
. "$REPO_ROOT/scripts/sh/hermes-agent.sh"
printf "%s\n%s\n" "$(dotfiles_hermes_data_dir)" "$(dotfiles_hermes_browser_data_dir)"
dotfiles_hermes_prepare_runtime_home
'

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "$TEST_HOME/custom-data" ]
	[ "${lines[1]}" = "$TEST_HOME/custom-browser" ]
	[ -d "$TEST_HOME/custom-data/.xurl" ]
	[ -d "$TEST_HOME/custom-browser" ]
}

@test "uses the Hermes data directory for the default browser directory" {
	export HERMES_DATA_DIR="$TEST_HOME/custom-data"

	run bash -c '
set -euo pipefail
. "$REPO_ROOT/scripts/sh/install-common.sh"
. "$REPO_ROOT/scripts/sh/hermes-agent.sh"
dotfiles_hermes_browser_data_dir
'

	[ "$status" -eq 0 ]
	[ "$output" = "$TEST_HOME/custom-data/.browser" ]
}

@test "fails preflight before Compose when op is unavailable" {
	rm "$STUB_BIN/op"

	run_start_stack

	[ "$status" -ne 0 ]
	[[ "$output" == *"1Password CLI (op) is required"* ]]
	[ ! -s "$COMMAND_LOG" ]
}

@test "fails preflight before Compose when jq is unavailable" {
	rm "$STUB_BIN/jq"
	export PATH="$STUB_BIN:/bin"

	run_start_stack

	[ "$status" -ne 0 ]
	[[ "$output" == *"jq is required"* ]]
	[ ! -s "$COMMAND_LOG" ]
}

@test "rejects a secret plan with an unsupported schema before looking up items" {
	export PLAN_JSON='{"schema_version":2,"items":[]}'

	run_start_stack

	[ "$status" -ne 0 ]
	[[ "$output" == *"secret plan is invalid"* ]]
	grep -q 'secret-plan' "$COMMAND_LOG"
	! grep -q '^op' "$COMMAND_LOG"
	! grep -q ' apply ' "$COMMAND_LOG"
	! grep -q ' up ' "$COMMAND_LOG"
}

@test "rejects malformed duplicate and wrong-count secret plans before looking up items" {
	export PLAN_JSON='{"schema_version":1,"items":[{"key":"dashboard","account":"my.1password.com","vault":"openclaw","item":"Hermes Agent Dashboard","fields":[]},{"key":"github","account":"my.1password.com","vault":"openclaw","item":"GitHubUsedOpenClawPAT","fields":[]},{"key":"slack_default","account":"my.1password.com","vault":"openclaw","item":"SlackBot-OpenClaw","fields":[]},{"key":"slack_rick","account":"my.1password.com","vault":"openclaw","item":"SlackBot-Rick","fields":[]},{"key":"slack_hoffman","account":"my.1password.com","vault":"openclaw","item":"SlackBot-Hoffman","fields":[]},{"key":"slack_risarisa","account":"my.1password.com","vault":"openclaw","item":"SlackBot-Risarisa","fields":[]}]}'
	assert_plan_rejected_before_secret_lookup

	export PLAN_JSON='{"schema_version":1,"items":[{"key":"dashboard","account":"my.1password.com","vault":"openclaw","item":"Hermes Agent Dashboard","fields":[{"canonical_name":"username","labels":["username"]}]},{"key":"dashboard","account":"my.1password.com","vault":"openclaw","item":"GitHubUsedOpenClawPAT","fields":[{"canonical_name":"credential","labels":["credential"]}]},{"key":"slack_default","account":"my.1password.com","vault":"openclaw","item":"SlackBot-OpenClaw","fields":[{"canonical_name":"bot_token","labels":["SLACK_BOT_TOKEN"]}]},{"key":"slack_rick","account":"my.1password.com","vault":"openclaw","item":"SlackBot-Rick","fields":[{"canonical_name":"bot_token","labels":["SLACK_BOT_TOKEN"]}]},{"key":"slack_hoffman","account":"my.1password.com","vault":"openclaw","item":"SlackBot-Hoffman","fields":[{"canonical_name":"bot_token","labels":["SLACK_BOT_TOKEN"]}]},{"key":"slack_risarisa","account":"my.1password.com","vault":"openclaw","item":"SlackBot-Risarisa","fields":[{"canonical_name":"bot_token","labels":["SLACK_BOT_TOKEN"]}]}]}'
	assert_plan_rejected_before_secret_lookup

	export PLAN_JSON='{"schema_version":1,"items":[]}'
	assert_plan_rejected_before_secret_lookup
}

@test "rejects two valid secret-plan documents without looking up items or applying" {
	valid_plan="$(valid_secret_plan)"
	export PLAN_JSON="$valid_plan
$valid_plan"

	assert_plan_rejected_before_secret_lookup
}

@test "rejects a valid secret plan followed by garbage without looking up items or applying" {
	export PLAN_JSON="$(valid_secret_plan)
trailing-garbage"

	assert_plan_rejected_before_secret_lookup
}

@test "propagates an op failure, closes the apply stream, and does not recreate services" {
	export OP_FAIL_ITEM='SlackBot-Rick'

	run_start_stack

	[ "$status" -ne 0 ]
	grep -q '<SlackBot-Rick>' "$COMMAND_LOG"
	grep -q '<apply>' "$COMMAND_LOG"
	! grep -q '<up>' "$COMMAND_LOG"
	! grep -q '"type":"end"' "$PAYLOAD_CAPTURE"
	! grep -q "$SECRET_MARKER" "$COMMAND_LOG"
	[[ "$output" != *"$SECRET_MARKER"* ]]
}

@test "does not recreate services when bootstrap apply fails" {
	export BOOTSTRAP_STATUS=42

	run_start_stack

	[ "$status" -eq 42 ]
	grep -q '<apply>' "$COMMAND_LOG"
	! grep -q '<up>' "$COMMAND_LOG"
	grep -q '<ps> <--all>' "$COMMAND_LOG"
	! grep -q "$SECRET_MARKER" "$COMMAND_LOG"
	[[ "$output" != *"$SECRET_MARKER"* ]]
}

@test "streams an ordered versioned payload and recreates services after success" {
	run_start_stack

	[ "$status" -eq 0 ]
	assert_log_order '<config> <--quiet>' '<build> <hermes> <hermes-bootstrap>' '<secret-plan>' '<apply>' '<Hermes Agent Dashboard>' '<GitHubUsedOpenClawPAT>' '<SlackBot-OpenClaw>' '<SlackBot-Rick>' '<SlackBot-Hoffman>' '<SlackBot-Risarisa>' '<up> <-d> <--force-recreate>'
	[ "$(grep -c '^op ' "$COMMAND_LOG")" -eq 6 ]
	mapfile -t records < <("$REAL_JQ" -r '.type + ":" + (.key // "")' "$PAYLOAD_CAPTURE")
	[ "${records[*]}" = 'header: item:dashboard item:github item:slack_default item:slack_rick item:slack_hoffman item:slack_risarisa end:' ]
	"$REAL_JQ" -e -c 'select(.type == "item") | .item.id == "item-id"' "$PAYLOAD_CAPTURE" >/dev/null
	! grep -q "$SECRET_MARKER" "$COMMAND_LOG"
	[[ "$output" != *"$SECRET_MARKER"* ]]
}

@test "forwards Docker calls through a function runner and retains host runtime paths" {
	run_start_stack_with_function_runner

	[ "$status" -eq 0 ]
	grep -q '^runner <compose> <-f> <' "$COMMAND_LOG"
	[ -d "$TEST_HOME/.hermes/.xurl" ]
	[ -d "$TEST_HOME/.hermes/.browser" ]
}

@test "removes host writers for dashboard Slack model profile and env content" {
	run bash -c '
set -euo pipefail
. "$REPO_ROOT/scripts/sh/install-common.sh"
. "$REPO_ROOT/scripts/sh/hermes-agent.sh"
for function_name in \
  dotfiles_hermes_ensure_dashboard_auth \
  dotfiles_hermes_ensure_slack_environment \
  dotfiles_hermes_ensure_runtime_configuration \
  dotfiles_hermes_write_dashboard_auth \
  dotfiles_hermes_write_slack_environment; do
  ! declare -F "$function_name" >/dev/null
done
'

	[ "$status" -eq 0 ]
}
