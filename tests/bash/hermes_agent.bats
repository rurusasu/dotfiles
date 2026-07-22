#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	TEST_HOME="$BATS_TEST_TMPDIR/home"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"
	PAYLOAD_CAPTURE="$BATS_TEST_TMPDIR/payload.ndjson"
	READY_ATTEMPT_FILE="$BATS_TEST_TMPDIR/ready-attempts"
	COMPOSE_FILE="$BATS_TEST_TMPDIR/compose file.yml"
	REAL_JQ="$(command -v jq)"
	SECRET_MARKER="adapter-secret-marker"
	mkdir -p "$TEST_HOME" "$STUB_BIN"
	: >"$COMMAND_LOG"
	: >"$PAYLOAD_CAPTURE"
	printf '0\n' >"$READY_ATTEMPT_FILE"
	: >"$COMPOSE_FILE"

	export REPO_ROOT HOME="$TEST_HOME" PATH="$STUB_BIN:/usr/bin:/bin"
	export COMMAND_LOG PAYLOAD_CAPTURE READY_ATTEMPT_FILE COMPOSE_FILE REAL_JQ SECRET_MARKER
	export PLAN_JSON="$(valid_secret_plan)"
	export OP_ITEM_JSON='{"id":"item-id","fields":[{"label":"credential","value":"adapter-secret-marker"}]}'
	export BOOTSTRAP_STATUS=0
	export OP_FAIL_ITEM=""
	export API_READY_AFTER=1
	export HERMES_API_READY_ATTEMPTS=3
	export HERMES_API_READY_DELAY_SECONDS=0
	export HERMES_API_PROBE_TIMEOUT_SECONDS=1

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
	write_stub curl '
attempt="$(cat "$READY_ATTEMPT_FILE")"
attempt=$((attempt + 1))
printf "%s\n" "$attempt" >"$READY_ATTEMPT_FILE"
printf "curl" >>"$COMMAND_LOG"
printf " <%s>" "$@" >>"$COMMAND_LOG"
printf "\n" >>"$COMMAND_LOG"
if ((attempt < API_READY_AFTER)); then
	exit 22
fi
'
	write_stub sleep '
printf "sleep <%s>\n" "$*" >>"$COMMAND_LOG"
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

write_fixture_stub() {
	local name="$1"
	local body="$2"
	cat >"$MOCK_BIN/$name" <<EOF
#!/usr/bin/env bash
set -euo pipefail
$body
EOF
	chmod +x "$MOCK_BIN/$name"
}

create_mocked_installer_fixture() {
	MOCK_REPO="$BATS_TEST_TMPDIR/installer-repo"
	MOCK_BIN="$BATS_TEST_TMPDIR/installer-bin"
	MOCK_DOCKER_APP="$BATS_TEST_TMPDIR/Docker.app"
	mkdir -p "$MOCK_REPO/scripts/sh" "$MOCK_REPO/chezmoi" \
		"$MOCK_REPO/docker/hermes-agent" "$MOCK_BIN" "$MOCK_DOCKER_APP/Contents/MacOS" \
		"$MOCK_DOCKER_APP/Contents/Resources/bin"
	MOCK_REPO="$(cd "$MOCK_REPO" && pwd -P)"
	cp "$REPO_ROOT/install.sh" "$MOCK_REPO/install.sh"
	cp "$REPO_ROOT/scripts/sh/install-common.sh" "$MOCK_REPO/scripts/sh/install-common.sh"
	for installer in install-macos.sh install-linux.sh install-nixos.sh; do
		cp "$REPO_ROOT/scripts/sh/$installer" "$MOCK_REPO/scripts/sh/$installer"
	done
	touch "$MOCK_REPO/flake.nix" "$MOCK_REPO/docker/hermes-agent/compose.yml"

	cat >"$MOCK_REPO/scripts/sh/hermes-agent.sh" <<'EOF'
printf 'selected-installer=%s\n' "${BASH_SOURCE[1]}" >>"$COMMAND_LOG"
dotfiles_hermes_start_stack() {
  printf 'adapter runner=%s compose=%s\n' "$1" "$2" >>"$COMMAND_LOG"
  "$1" compose -f "$2" config --quiet
}
EOF
	cat >"$MOCK_REPO/scripts/sh/verify-environment.sh" <<'EOF'
#!/usr/bin/env bash
printf 'verify-environment %s\n' "$*" >>"$COMMAND_LOG"
EOF
	chmod +x "$MOCK_REPO/install.sh" "$MOCK_REPO/scripts/sh/verify-environment.sh"

	write_fixture_stub uname '
case "${1:-}" in
  -s) printf "%s\\n" "$MOCK_UNAME_S" ;;
  -m) printf "%s\\n" "$MOCK_UNAME_M" ;;
  *) exit 2 ;;
esac
'
	write_fixture_stub sw_vers 'printf "26.5.1\\n"'
	write_fixture_stub xcode-select 'printf "/Library/Developer/CommandLineTools\\n"'
	write_fixture_stub pgrep 'exit 1'
	write_fixture_stub systemctl '
printf "systemctl %s\\n" "$*" >>"$COMMAND_LOG"
case "${1:-}" in
  is-system-running) printf "running\\n" ;;
esac
'
	write_fixture_stub id '
case "${1:-}" in
  -u | -g) printf "1000\\n" ;;
  -gn) printf "users\\n" ;;
  -Gn) printf "test-user docker\\n" ;;
  *) /usr/bin/id "$@" ;;
esac
'
	write_fixture_stub nix '
printf "nix %s\\n" "$*" >>"$COMMAND_LOG"
if [[ $* == *"builtins.currentSystem"* ]]; then
  printf "x86_64-linux"
fi
'
	write_fixture_stub nixos-rebuild 'printf "unexpected nixos-rebuild\\n" >>"$COMMAND_LOG"; exit 99'
	write_fixture_stub sudo 'printf "sudo %s\\n" "$*" >>"$COMMAND_LOG"; exec "$@"'
	write_fixture_stub chezmoi 'printf "chezmoi %s\\n" "$*" >>"$COMMAND_LOG"'
	write_fixture_stub docker 'printf "docker %s\\n" "$*" >>"$COMMAND_LOG"'

	cat >"$MOCK_DOCKER_APP/Contents/MacOS/install" <<'EOF'
#!/usr/bin/env bash
printf 'docker-install %s\n' "$*" >>"$COMMAND_LOG"
EOF
	cat >"$MOCK_DOCKER_APP/Contents/Resources/bin/docker" <<'EOF'
#!/usr/bin/env bash
printf 'docker %s\n' "$*" >>"$COMMAND_LOG"
EOF
	chmod +x "$MOCK_DOCKER_APP/Contents/MacOS/install" \
		"$MOCK_DOCKER_APP/Contents/Resources/bin/docker"
}

run_mocked_installer() {
	local platform="$1"
	local marker="$BATS_TEST_TMPDIR/NIXOS"
	local hardware="$BATS_TEST_TMPDIR/hardware-configuration.nix"
	local prebuilt="$BATS_TEST_TMPDIR/prebuilt-system"
	local systemd_dir="$BATS_TEST_TMPDIR/systemd"
	local os_release="$BATS_TEST_TMPDIR/os-release"

	create_mocked_installer_fixture
	printf '{ ... }: { }\n' >"$hardware"
	mkdir -p "$prebuilt/bin" "$systemd_dir"
	cat >"$prebuilt/bin/switch-to-configuration" <<'EOF'
#!/usr/bin/env bash
printf 'switch-to-configuration %s\n' "$*" >>"$COMMAND_LOG"
EOF
	chmod +x "$prebuilt/bin/switch-to-configuration"
	printf 'ID=ubuntu\n' >"$os_release"
	MOCK_NIXOS_MARKER="$marker"

	case "$platform" in
	macos)
		rm -f "$marker"
		export MOCK_UNAME_S=Darwin MOCK_UNAME_M=arm64
		MOCK_SELECTED_INSTALLER=install-macos.sh
		;;
	linux)
		rm -f "$marker"
		export MOCK_UNAME_S=Linux MOCK_UNAME_M=x86_64
		MOCK_SELECTED_INSTALLER=install-linux.sh
		;;
	nixos)
		touch "$marker"
		export MOCK_UNAME_S=Linux MOCK_UNAME_M=x86_64
		MOCK_SELECTED_INSTALLER=install-nixos.sh
		;;
	*) false ;;
	esac

	run env \
		HOME="$TEST_HOME" \
		USER=test-user \
		PATH="$MOCK_BIN:/usr/bin:/bin" \
		COMMAND_LOG="$COMMAND_LOG" \
		MOCK_UNAME_S="$MOCK_UNAME_S" \
		MOCK_UNAME_M="$MOCK_UNAME_M" \
		DOTFILES_CHECKOUT_TARGET="$BATS_TEST_TMPDIR/checkout" \
		DOTFILES_NIX_PROFILE_SCRIPT="$BATS_TEST_TMPDIR/nix-daemon.sh" \
		DOTFILES_DOCKER_APP_PATH="$MOCK_DOCKER_APP" \
		DOTFILES_DOCKER_SETUP_MARKER="$BATS_TEST_TMPDIR/docker-setup" \
		DOTFILES_SYSTEMD_DIR="$systemd_dir" \
		DOTFILES_OS_RELEASE_FILE="$os_release" \
		DOTFILES_NIXOS_MARKER="$marker" \
		DOTFILES_NIXOS_HARDWARE_CONFIG="$hardware" \
		DOTFILES_NIXOS_PREBUILT_SYSTEM="$prebuilt" \
		"$MOCK_REPO/install.sh"
}

@test "Unix installers source the shared adapter and use one canonical handoff" {
	local installer expected_runner expected_call contents
	for installer in install-macos.sh install-linux.sh install-nixos.sh; do
		contents="$REPO_ROOT/scripts/sh/$installer"
		grep -Fq '. "$ROOT/scripts/sh/hermes-agent.sh"' "$contents"
		! grep -Eq '^start_hermes_stack[[:space:]]*\(\)' "$contents"
		! grep -Eq 'dotfiles_hermes_(ensure|write)_' "$contents"
		[ "$(grep -c 'dotfiles_hermes_start_stack' "$contents")" -eq 1 ]

		case "$installer" in
		install-macos.sh)
			expected_runner=docker
			grep -Fq 'setup_docker_runtime()' "$contents"
			grep -Fq 'docker compose version >/dev/null' "$contents"
			;;
		*)
			expected_runner=docker_command
			grep -Fq 'dotfiles_run_in_group docker docker "$@"' "$contents"
			;;
		esac
		expected_call="dotfiles_hermes_start_stack $expected_runner \"\$DOTFILES_ROOT/docker/hermes-agent/compose.yml\""
		grep -Fq "$expected_call" "$contents"
	done
}

@test "install.sh routes each Unix installer through the shared adapter after chezmoi" {
	local platform expected_runner adapter_line apply_line
	for platform in macos linux nixos; do
		: >"$COMMAND_LOG"
		run_mocked_installer "$platform"

		[ "$status" -eq 0 ]
		case "$platform" in
		macos) expected_runner=docker ;;
		*) expected_runner=docker_command ;;
		esac
		adapter_line="adapter runner=$expected_runner compose=$MOCK_REPO/docker/hermes-agent/compose.yml"
		grep -Fxq "selected-installer=$MOCK_REPO/scripts/sh/$MOCK_SELECTED_INSTALLER" "$COMMAND_LOG"
		grep -Fxq "$adapter_line" "$COMMAND_LOG"
		grep -Fq "docker compose -f $MOCK_REPO/docker/hermes-agent/compose.yml config --quiet" "$COMMAND_LOG"
		apply_line="$(grep -n -m 1 '^chezmoi apply --force$' "$COMMAND_LOG" | cut -d: -f1)"
		[ -n "$apply_line" ]
		[ "$(grep -n -m 1 -F "$adapter_line" "$COMMAND_LOG" | cut -d: -f1)" -gt "$apply_line" ]
		! grep -q '^unexpected nixos-rebuild$' "$COMMAND_LOG"
		if [[ $platform == macos ]]; then
			grep -Fxq 'docker info' "$COMMAND_LOG"
			grep -Fxq 'docker compose version' "$COMMAND_LOG"
		fi
		if [[ $platform == nixos ]]; then
			[ -e "$MOCK_NIXOS_MARKER" ]
		else
			[ ! -e "$MOCK_NIXOS_MARKER" ]
		fi
	done
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
	export BOOTSTRAP_STATUS=2

	run_start_stack

	[ "$status" -eq 1 ]
	grep -q '<SlackBot-Rick>' "$COMMAND_LOG"
	grep -q '<apply>' "$COMMAND_LOG"
	! grep -q '<up>' "$COMMAND_LOG"
	! grep -q '"type":"end"' "$PAYLOAD_CAPTURE"
	! grep -q "$SECRET_MARKER" "$COMMAND_LOG"
	[[ "$output" != *"$SECRET_MARKER"* ]]
}

@test "propagates bootstrap migration exit five without recreating services" {
	export BOOTSTRAP_STATUS=5

	run_start_stack

	[ "$status" -eq 5 ]
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

@test "waits for the Hermes API to become ready before reporting success" {
	export API_READY_AFTER=3

	run_start_stack

	[ "$status" -eq 0 ]
	[ "$(cat "$READY_ATTEMPT_FILE")" -eq 3 ]
	[ "$(grep -c '^curl ' "$COMMAND_LOG")" -eq 3 ]
	grep -q '<http://127.0.0.1:8642/health>' "$COMMAND_LOG"
	[ "$(grep -c '^sleep ' "$COMMAND_LOG")" -eq 2 ]
	assert_log_order '<up> <-d> <--force-recreate>' '^curl '
	! grep -q "$SECRET_MARKER" "$COMMAND_LOG"
	[[ "$output" != *"$SECRET_MARKER"* ]]
}

@test "fails after bounded Hermes API readiness attempts with redacted diagnostics" {
	export API_READY_AFTER=99
	export HERMES_API_READY_ATTEMPTS=3

	run_start_stack

	[ "$status" -ne 0 ]
	[ "$(cat "$READY_ATTEMPT_FILE")" -eq 3 ]
	[ "$(grep -c '^sleep ' "$COMMAND_LOG")" -eq 2 ]
	grep -q '<ps> <--all>' "$COMMAND_LOG"
	[[ "$output" == *"Hermes API did not become ready after 3 attempts."* ]]
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
