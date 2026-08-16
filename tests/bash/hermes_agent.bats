#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	TEST_HOME="$BATS_TEST_TMPDIR/home"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"
	EDIT_CAPTURE="$BATS_TEST_TMPDIR/item-edit.json"
	PAYLOAD_CAPTURE="$BATS_TEST_TMPDIR/payload.ndjson"
	READY_ATTEMPT_FILE="$BATS_TEST_TMPDIR/ready-attempts"
	OLLAMA_READY_ATTEMPT_FILE="$BATS_TEST_TMPDIR/ollama-ready-attempts"
	HINDSIGHT_READY_ATTEMPT_FILE="$BATS_TEST_TMPDIR/hindsight-ready-attempts"
	COMPOSE_FILE="$BATS_TEST_TMPDIR/compose file.yml"
	REAL_JQ="$(command -v jq)"
	REAL_PYTHON3="$(command -v python3)"
	SECRET_MARKER="adapter-secret-marker"
	mkdir -p "$TEST_HOME/.hermes" "$STUB_BIN"
	: >"$COMMAND_LOG"
	: >"$PAYLOAD_CAPTURE"
	printf '0\n' >"$READY_ATTEMPT_FILE"
	printf '0\n' >"$OLLAMA_READY_ATTEMPT_FILE"
	printf '0\n' >"$HINDSIGHT_READY_ATTEMPT_FILE"
	: >"$COMPOSE_FILE"
	cat >"$BATS_TEST_TMPDIR/hindsight.env" <<'EOF'
HINDSIGHT_API_LLM_MODEL=qwen3.6:35b
HINDSIGHT_API_EMBEDDINGS_OPENAI_MODEL=qwen3-embedding:0.6b
EOF

	export REPO_ROOT HOME="$TEST_HOME" PATH="$STUB_BIN:/usr/bin:/bin"
	unset DOTFILES_USER SUDO_USER
	unset DOTFILES_HERMES_OLLAMA_EXECUTABLE DOTFILES_HERMES_CURL_EXECUTABLE OLLAMA_HOST
	export HINDSIGHT_OLLAMA_URL=http://127.0.0.1:11434
	export COMMAND_LOG EDIT_CAPTURE PAYLOAD_CAPTURE READY_ATTEMPT_FILE OLLAMA_READY_ATTEMPT_FILE HINDSIGHT_READY_ATTEMPT_FILE COMPOSE_FILE REAL_JQ REAL_PYTHON3 SECRET_MARKER
	export DOTFILES_SKIP_HERDR_INSTALL=1
	export PLAN_JSON="$(valid_secret_plan)"
	export OP_ITEM_JSON='{"id":"item-id","fields":[{"label":"credential","value":"adapter-secret-marker"}]}'
	export XAPI_OP_ITEM_JSON='{"id":"xapi-item","fields":[{"label":"X_API_CLIENT_ID","value":"xapi-client-id-marker"},{"label":"X_API_CLIENT_SECRET","value":"xapi-client-secret-marker"},{"label":"X_API_REFRESH_TOKEN","section":{"label":"Refresh Token"},"value":"xapi-refresh-token-marker"}]}'
	export XAPI_OAUTH_ITEM_JSON='{"id":"xapi-oauth-item","fields":[{"label":"X_API_REFRESH_TOKEN","value":"xapi-refresh-token-marker"}]}'
	export BOOTSTRAP_STATUS=0
	export OP_FAIL_ITEM=""
	export OP_DELAY_SECONDS=0
	export OP_READ_TOKEN='service-account-token'
	export OP_READ_DELAY_SECONDS=0
	export OP_READ_COMPLETION_FILE=""
	export BOOTSTRAP_EXIT_EARLY=0
	export HERMES_RUNTIME_EXISTS=1
	export API_READY_AFTER=1
	export OLLAMA_READY_AFTER=1
	export HINDSIGHT_API_DATABASE=connected
	export HINDSIGHT_API_READY_AFTER=1
	export OLLAMA_PULL_FAILURE=""
	export OLLAMA_PULL_TIMEOUT_STATUS=0
	export HERMES_API_READY_ATTEMPTS=3
	export HERMES_API_READY_DELAY_SECONDS=0
	export HERMES_API_PROBE_TIMEOUT_SECONDS=1
	export IMAGE_PRUNE_STATUS=0
	export UP_STATUS=0

	write_stub jq '
exec "$REAL_JQ" "$@"
'
	write_stub python3 'exec "$REAL_PYTHON3" "$@"'
	write_stub op '
printf "op" >>"$COMMAND_LOG"
printf " <%s>" "$@" >>"$COMMAND_LOG"
printf "\n" >>"$COMMAND_LOG"
	case "${3:-}" in
	read)
		if [[ ${OP_READ_DELAY_SECONDS:-0} != 0 ]]; then
			/bin/sleep "$OP_READ_DELAY_SECONDS"
		fi
		if [[ -n ${OP_READ_COMPLETION_FILE:-} ]]; then
			printf "completed\n" >"$OP_READ_COMPLETION_FILE"
		fi
		printf "%s\n" "$OP_READ_TOKEN"
		;;
	*)
		if [ "${1:-}" = item ] && [ "${2:-}" = edit ]; then
			cat >"$EDIT_CAPTURE"
			exit 0
		fi
		[ "${2:-}" = get ] || exit 2
		if [ "${3:-}" = "$OP_FAIL_ITEM" ]; then
			exit 17
		fi
		if [[ $OP_DELAY_SECONDS != 0 ]]; then
			/bin/sleep "$OP_DELAY_SECONDS"
		fi
		if [ "${3:-}" = "Hermes X API MCP" ]; then
			printf "%s\n" "$XAPI_OP_ITEM_JSON"
		elif [ "${3:-}" = "Hermes X API MCP OAuth" ]; then
			printf "%s\n" "$XAPI_OAUTH_ITEM_JSON"
		else
			printf "%s\n" "$OP_ITEM_JSON"
		fi
		;;
esac
'
	write_stub docker '
printf "docker" >>"$COMMAND_LOG"
printf " <%s>" "$@" >>"$COMMAND_LOG"
printf "\n" >>"$COMMAND_LOG"
if [ "${1:-}" = "image" ] && [ "${2:-}" = "prune" ]; then
	exit "$IMAGE_PRUNE_STATUS"
fi
if [ "${1:-}" != "compose" ]; then
	exit 1
fi
case " $* " in
  *" up -d --force-recreate "*)
    exit "$UP_STATUS"
    ;;
  *" ps --all --services hermes "*)
    if [[ $HERMES_RUNTIME_EXISTS == 1 ]]; then
      printf "hermes\n"
    fi
    ;;
  *" secret-plan "*) printf "%s\n" "$PLAN_JSON" ;;
  *" apply "*)
    if [[ $BOOTSTRAP_EXIT_EARLY == 1 ]]; then
      exit "$BOOTSTRAP_STATUS"
    fi
    cat >"$PAYLOAD_CAPTURE"
    exit "$BOOTSTRAP_STATUS"
    ;;
esac
'
	write_stub curl '
case " $* " in
  *"/api/version "*)
    attempt="$(cat "$OLLAMA_READY_ATTEMPT_FILE")"
    attempt=$((attempt + 1))
    printf "%s\n" "$attempt" >"$OLLAMA_READY_ATTEMPT_FILE"
    printf "curl" >>"$COMMAND_LOG"
    printf " <%s>" "$@" >>"$COMMAND_LOG"
    printf "\n" >>"$COMMAND_LOG"
    if ((attempt < OLLAMA_READY_AFTER)); then exit 22; fi
    printf "{\"version\":\"0.1\"}\n"
    exit 0
    ;;
  *"/api/tags "*)
    printf "curl" >>"$COMMAND_LOG"
    printf " <%s>" "$@" >>"$COMMAND_LOG"
    printf "\n" >>"$COMMAND_LOG"
    printf "{\"models\":[{\"name\":\"qwen3.6:35b\"},{\"name\":\"qwen3-embedding:0.6b\"}]}\n"
    exit 0
    ;;
  *"127.0.0.1:8888/health "*)
		attempt="$(cat "$HINDSIGHT_READY_ATTEMPT_FILE")"
		attempt=$((attempt + 1))
		printf "%s\n" "$attempt" >"$HINDSIGHT_READY_ATTEMPT_FILE"
    printf "curl" >>"$COMMAND_LOG"
    printf " <%s>" "$@" >>"$COMMAND_LOG"
    printf "\n" >>"$COMMAND_LOG"
		if ((attempt < HINDSIGHT_API_READY_AFTER)); then exit 22; fi
    printf "{\"status\":\"healthy\",\"database\":\"%s\"}\n" "$HINDSIGHT_API_DATABASE"
    exit 0
    ;;
esac
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
	write_stub ollama '
printf "ollama" >>"$COMMAND_LOG"
printf " <%s>" "$@" >>"$COMMAND_LOG"
printf "\n" >>"$COMMAND_LOG"
if [[ ${1:-} == pull && ${2:-} == "$OLLAMA_PULL_FAILURE" ]]; then exit 42; fi
'
	write_stub timeout '
if [[ ${1:-} == --version ]]; then
	printf "timeout (GNU coreutils) 9.0\n"
	exit 0
fi
printf "timeout" >>"$COMMAND_LOG"
printf " <%s>" "$@" >>"$COMMAND_LOG"
printf "\n" >>"$COMMAND_LOG"
if [[ ${OLLAMA_PULL_TIMEOUT_STATUS:-0} != 0 ]]; then
	exit "$OLLAMA_PULL_TIMEOUT_STATUS"
fi
[[ ${1:-} == --foreground ]] && shift
[[ ${1:-} == --kill-after=30 ]] && shift
shift
"$@"
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
{"schema_version":1,"items":[{"key":"dashboard","account":"my.1password.com","vault":"openclaw","item":"Hermes Agent Dashboard","fields":[{"canonical_name":"username","labels":["username"]},{"canonical_name":"password","labels":["password"]}]},{"key":"github","account":"my.1password.com","vault":"openclaw","item":"GitHubUsedOpenClawPAT","fields":[{"canonical_name":"credential","labels":["credential"]}]},{"key":"google_calendar","account":"my.1password.com","vault":"Private","item":"Google Calendar MCP","fields":[{"canonical_name":"oauth_credentials_json","labels":["oauth_credentials_json"]},{"canonical_name":"tokens_json","labels":["tokens_json"]}]},{"key":"discord_default","account":"my.1password.com","vault":"openclaw","item":"Master","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]}]},{"key":"discord_rick","account":"my.1password.com","vault":"openclaw","item":"Rick","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]}]},{"key":"discord_hoffman","account":"my.1password.com","vault":"openclaw","item":"Hoffman","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]}]},{"key":"discord_risarisa","account":"my.1password.com","vault":"openclaw","item":"RisaRisa","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]}]},{"key":"discord_nancy","account":"my.1password.com","vault":"openclaw","item":"Nancy","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]}]},{"key":"discord_kuroda","account":"my.1password.com","vault":"openclaw","item":"Kuroda","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]}]},{"key":"discord_shiraishi","account":"my.1password.com","vault":"openclaw","item":"Shiraishi","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]}]}]}
JSON
}

run_start_stack() {
	local missing_command="${1:-}"
	run env DOTFILES_TEST_MISSING_COMMAND="$missing_command" bash -c '
set -euo pipefail
. "$REPO_ROOT/scripts/sh/install-common.sh"
. "$REPO_ROOT/scripts/sh/hermes-agent.sh"
if [[ -n ${DOTFILES_TEST_MISSING_COMMAND:-} ]]; then
  dotfiles_have() {
    [[ $1 != "$DOTFILES_TEST_MISSING_COMMAND" ]] && command -v "$1" >/dev/null 2>&1
  }
fi
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

service_account_cache_mode() {
	stat -c '%a' "$HOME/.hermes/.op.env" 2>/dev/null ||
		stat -f '%Lp' "$HOME/.hermes/.op.env"
}

service_account_cache_inode() {
	stat -c '%i' "$1" 2>/dev/null || stat -f '%i' "$1"
}

assert_service_account_cache_rejected_after_timeout() {
	export OP_READ_DELAY_SECONDS=2 DOTFILES_HERMES_OP_READ_TIMEOUT_SECONDS=1
	run_start_stack
	[ "$status" -ne 0 ]
	! grep -q '<compose>' "$COMMAND_LOG"
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
	local fixture_root="$1"
	MOCK_REPO="$fixture_root/installer-repo"
	MOCK_BIN="$fixture_root/installer-bin"
	MOCK_DOCKER_APP="$fixture_root/Docker.app"
	mkdir -p "$MOCK_REPO/scripts/sh" "$MOCK_REPO/chezmoi" \
		"$MOCK_REPO/docker/hermes-agent" "$MOCK_BIN" "$MOCK_DOCKER_APP/Contents/MacOS" \
		"$MOCK_DOCKER_APP/Contents/Resources/bin"
	MOCK_REPO="$(cd "$MOCK_REPO" && pwd -P)"
	cp "$REPO_ROOT/install.sh" "$MOCK_REPO/install.sh"
	cp "$REPO_ROOT/scripts/sh/install-common.sh" "$MOCK_REPO/scripts/sh/install-common.sh"
	for installer in install-macos.sh install-linux.sh install-nixos.sh; do
		cp "$REPO_ROOT/scripts/sh/$installer" "$MOCK_REPO/scripts/sh/$installer"
	done
	mv "$MOCK_REPO/scripts/sh/install-macos.sh" \
		"$MOCK_REPO/scripts/sh/install-macos-under-test.sh"
	cat >"$MOCK_REPO/scripts/sh/install-macos.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

export DOTFILES_TEST_SELECTED_INSTALLER="$0"
. "$(dirname "$0")/install-macos-under-test.sh"
ensure_docker_desktop_md5_compatibility() {
  :
}
homebrew_cask_link_parent_metadata() {
  printf '0 755\n'
}
homebrew_cask_link_parent_acl_state() {
  printf 'absent\n'
}
homebrew_cask_link_parent_is_immutable_to_caller() {
  return 0
}
main "$@"
EOF
	touch "$MOCK_REPO/flake.nix" "$MOCK_REPO/docker/hermes-agent/compose.yml"

	cat >"$MOCK_REPO/scripts/sh/hermes-agent.sh" <<'EOF'
printf 'selected-installer=%s\n' "${DOTFILES_TEST_SELECTED_INSTALLER:-${BASH_SOURCE[1]}}" >>"$COMMAND_LOG"
dotfiles_hermes_start_stack() {
  printf 'adapter runner=%s compose=%s\n' "$1" "$2" >>"$COMMAND_LOG"
  "$1" compose -f "$2" config --quiet
}
EOF
	cat >"$MOCK_REPO/scripts/sh/verify-environment.sh" <<'EOF'
#!/usr/bin/env bash
printf 'verify-environment %s\n' "$*" >>"$COMMAND_LOG"
EOF
	cat >"$MOCK_REPO/scripts/sh/update-homebrew-casks.sh" <<'EOF'
#!/usr/bin/env bash
printf 'update-homebrew-casks %s\n' "$*" >>"$COMMAND_LOG"
EOF
	chmod +x "$MOCK_REPO/install.sh" \
		"$MOCK_REPO/scripts/sh/install-macos.sh" \
		"$MOCK_REPO/scripts/sh/update-homebrew-casks.sh" \
		"$MOCK_REPO/scripts/sh/verify-environment.sh"

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
write_fixture_stub sudo '
printf "sudo" >>"$COMMAND_LOG"
printf " <%s>" "$@" >>"$COMMAND_LOG"
printf "\\n" >>"$COMMAND_LOG"
is_allowed_cask_target() {
  [[ $1 == /usr/local/bin || $1 == /usr/local/cli-plugins ||
    $1 == "${DOTFILES_HOMEBREW_BIN_DIR:-}" ||
    $1 == "${DOTFILES_HOMEBREW_CLI_PLUGINS_DIR:-}" ]]
}
fixture_user="${DOTFILES_USER:-${SUDO_USER:-$USER}}"
case "${1:-}" in
  /bin/mkdir)
    if [[ $# -eq 3 && ${2:-} == -- ]] && is_allowed_cask_target "${3:-}"; then
      exit 0
    fi
    ;;
  /usr/sbin/chown)
    if [[ $# -eq 3 && ${2:-} == "$fixture_user:admin" ]] && is_allowed_cask_target "${3:-}"; then
      exit 0
    fi
    ;;
  /bin/chmod)
    if [[ $# -eq 3 && ${2:-} == 0775 ]] && is_allowed_cask_target "${3:-}"; then
      exit 0
    fi
    ;;
  /usr/bin/env)
    if [[ $# -eq 13 && ${2:-} == "NIX_CONFIG=extra-experimental-features = nix-command flakes" &&
      ${3:-} == "DOTFILES_USER=$fixture_user" && ${4:-} == "DOTFILES_HOME=$HOME" &&
      ${5:-} == "DOTFILES_ROOT=$DOTFILES_ROOT" && ${6:-} == "${PATH%%:*}/nix" &&
      ${7:-} == run && ${8:-} == .#darwin-rebuild && ${9:-} == -- &&
      ${10:-} == switch && ${11:-} == --flake && ${12:-} == .#macos && ${13:-} == --impure ]]; then
      exec "$@"
    fi
    ;;
  "${DOTFILES_DOCKER_APP_PATH:-}/Contents/MacOS/install")
    if [[ $# -eq 3 && ${2:-} == --accept-license && ${3:-} == "--user=$fixture_user" ]]; then
      exec "$@"
    fi
    ;;
  "${DOTFILES_NIXOS_PREBUILT_SYSTEM:-}/bin/switch-to-configuration")
    if [[ $# -eq 2 && ${2:-} == switch ]]; then
      exec "$@"
    fi
    ;;
esac
printf "Unexpected sudo argv:" >&2
printf " <%s>" "$@" >&2
printf "\\n" >&2
exit 97
'
	write_fixture_stub chezmoi 'printf "chezmoi %s\\n" "$*" >>"$COMMAND_LOG"'
	write_fixture_stub docker 'printf "docker %s\\n" "$*" >>"$COMMAND_LOG"'
	write_fixture_stub task 'printf "task %s\\n" "$*" >>"$COMMAND_LOG"'

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
	local test_root fixture_root marker hardware prebuilt systemd_dir os_release user_profile_root
	local homebrew_bin_dir homebrew_cli_plugins_dir
	test_root="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"
	fixture_root="$test_root/installer-$platform"
	marker="$fixture_root/NIXOS"
	hardware="$fixture_root/hardware-configuration.nix"
	prebuilt="$fixture_root/prebuilt-system"
	MOCK_NIXOS_PREBUILT_SYSTEM="$prebuilt"
	systemd_dir="$fixture_root/systemd"
	os_release="$fixture_root/os-release"
	user_profile_root="$fixture_root/profiles"
	homebrew_bin_dir="$fixture_root/usr/local/bin"
	homebrew_cli_plugins_dir="$fixture_root/usr/local/cli-plugins"

	create_mocked_installer_fixture "$fixture_root"
	printf '{ ... }: { }\n' >"$hardware"
	mkdir -p "$prebuilt/bin" "$systemd_dir" "$user_profile_root/test-user" \
		"$homebrew_bin_dir" "$homebrew_cli_plugins_dir"
	ln -s "$MOCK_BIN" "$user_profile_root/test-user/bin"
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
		DOTFILES_CHECKOUT_TARGET="$fixture_root/checkout" \
		DOTFILES_NIX_PROFILE_SCRIPT="$fixture_root/nix-daemon.sh" \
		DOTFILES_DOCKER_APP_PATH="$MOCK_DOCKER_APP" \
		DOTFILES_DOCKER_SETUP_MARKER="$fixture_root/docker-setup" \
		DOTFILES_HOMEBREW_CASK_BIN_DIR="$fixture_root/untrusted/bin" \
		DOTFILES_HOMEBREW_CASK_CLI_PLUGIN_DIR="$fixture_root/untrusted/cli-plugins" \
		DOTFILES_BASHRC_PATH="$fixture_root/etc/bashrc" \
		DOTFILES_ZSHRC_PATH="$fixture_root/etc/zshrc" \
		DOTFILES_USER_PROFILE_ROOT="$user_profile_root" \
		DOTFILES_HOMEBREW_BIN_DIR="$homebrew_bin_dir" \
		DOTFILES_HOMEBREW_CLI_PLUGINS_DIR="$homebrew_cli_plugins_dir" \
		DOTFILES_SYSTEMD_DIR="$systemd_dir" \
		DOTFILES_OS_RELEASE_FILE="$os_release" \
		DOTFILES_NIXOS_MARKER="$marker" \
		DOTFILES_NIXOS_HARDWARE_CONFIG="$hardware" \
		DOTFILES_NIXOS_PREBUILT_SYSTEM="$MOCK_NIXOS_PREBUILT_SYSTEM" \
		"$MOCK_REPO/install.sh"
}

@test "Unix installers use the Taskfile as the canonical Hermes handoff" {
	local installer contents
	for installer in install-macos.sh install-linux.sh install-nixos.sh; do
		contents="$REPO_ROOT/scripts/sh/$installer"
		! grep -Fq 'hermes-agent.sh' "$contents"
			grep -Fq 'dotfiles_run_task hermes:bootstrap' "$contents" ||
				grep -Fq 'dotfiles_run_task_in_group docker hermes:bootstrap' "$contents"
	done
}

@test "install.sh routes each Unix installer through the Taskfile after chezmoi" {
	local platform task_line apply_line task_line_number expected_sudo_count target
	for platform in macos linux nixos; do
		: >"$COMMAND_LOG"
		run_mocked_installer "$platform"

		if [[ $status -ne 0 ]]; then
			printf '%s installer failed:\n%s\n' "$platform" "$output" >&3
			false
		fi
		task_line="task --dir $MOCK_REPO hermes:bootstrap"
		grep -Fxq "$task_line" "$COMMAND_LOG"
		apply_line="$(grep -n -m 1 '^chezmoi apply --force$' "$COMMAND_LOG" | cut -d: -f1)"
		[ -n "$apply_line" ]
		task_line_number="$(grep -n -m 1 -F "$task_line" "$COMMAND_LOG" | cut -d: -f1)"
		[ "$task_line_number" -gt "$apply_line" ]
		! grep -q '^unexpected nixos-rebuild$' "$COMMAND_LOG"
		if [[ $platform == macos ]]; then
			grep -Fxq 'docker info' "$COMMAND_LOG"
			grep -Fxq 'docker compose version' "$COMMAND_LOG"
			grep -Fqx "sudo </usr/bin/env> <NIX_CONFIG=extra-experimental-features = nix-command flakes> <DOTFILES_USER=test-user> <DOTFILES_HOME=$TEST_HOME> <DOTFILES_ROOT=$MOCK_REPO> <$MOCK_BIN/nix> <run> <.#darwin-rebuild> <--> <switch> <--flake> <.#macos> <--impure>" "$COMMAND_LOG"
			grep -Fqx 'sudo </usr/sbin/chown> <test-user:admin> </usr/local/bin>' "$COMMAND_LOG"
			grep -Fqx 'sudo </bin/chmod> <0775> </usr/local/bin>' "$COMMAND_LOG"
			grep -Fqx 'sudo </usr/sbin/chown> <test-user:admin> </usr/local/cli-plugins>' "$COMMAND_LOG"
			grep -Fqx 'sudo </bin/chmod> <0775> </usr/local/cli-plugins>' "$COMMAND_LOG"
			grep -Fqx "sudo <$MOCK_DOCKER_APP/Contents/MacOS/install> <--accept-license> <--user=test-user>" "$COMMAND_LOG"
				expected_sudo_count=10
			for target in /usr/local/bin /usr/local/cli-plugins; do
				if [[ ! -e $target ]]; then
					grep -Fqx "sudo </bin/mkdir> <--> <$target>" "$COMMAND_LOG"
					expected_sudo_count=$((expected_sudo_count + 1))
				fi
			done
			[ "$(grep -c '^sudo ' "$COMMAND_LOG")" -eq "$expected_sudo_count" ]
			! grep -Fq "$BATS_TEST_TMPDIR/installer-macos/untrusted" "$COMMAND_LOG"
		fi
		if [[ $platform == linux ]]; then
			[ "$(grep -c '^sudo ' "$COMMAND_LOG" || true)" -eq 0 ]
		fi
		if [[ $platform == nixos ]]; then
			[ -e "$MOCK_NIXOS_MARKER" ]
			grep -Fqx "sudo <$MOCK_NIXOS_PREBUILT_SYSTEM/bin/switch-to-configuration> <switch>" "$COMMAND_LOG"
			[ "$(grep -c '^sudo ' "$COMMAND_LOG")" -eq 1 ]
		else
			[ ! -e "$MOCK_NIXOS_MARKER" ]
		fi
	done
}

@test "mocked macOS installer accepts the sudo user for cask directory repair" {
	local runner_user="runner"

	export SUDO_USER="$runner_user"
	run_mocked_installer macos

	[ "$status" -eq 0 ]
	grep -Fqx "sudo </usr/sbin/chown> <$runner_user:admin> </usr/local/bin>" "$COMMAND_LOG"
	grep -Fqx "sudo </usr/sbin/chown> <$runner_user:admin> </usr/local/cli-plugins>" "$COMMAND_LOG"
}

@test "mocked installer sudo boundary rejects unknown argv" {
	local fixture_root="$BATS_TEST_TMPDIR/unknown-sudo"
	local unexpected="$fixture_root/unexpected-touch"
	create_mocked_installer_fixture "$fixture_root"

	run env -i \
		PATH="$PATH" \
		HOME="$HOME" \
		USER=test-user \
		COMMAND_LOG="$COMMAND_LOG" \
		"$MOCK_BIN/sudo" /usr/bin/touch "$unexpected"

	[ "$status" -eq 97 ]
	[[ "$output" == *"Unexpected sudo argv: </usr/bin/touch> <$unexpected>"* ]]
	[ ! -e "$unexpected" ]
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

@test "injects X API OAuth credentials from 1Password for explicit wrapper commands" {
	export XAPI_OP_ITEM_JSON='{"id":"xapi-item","fields":[{"label":"X_API_CLIENT_ID","value":"xapi-client-id-marker"},{"label":"X_API_CLIENT_SECRET","value":"xapi-client-secret-marker"}]}'

	run bash -c '
set -euo pipefail
. "$REPO_ROOT/scripts/sh/install-common.sh"
. "$REPO_ROOT/scripts/sh/hermes-agent.sh"
dotfiles_hermes_with_xapi_credentials bash -c '"'"'printf "%s:%s\n" "$X_API_CLIENT_ID" "$X_API_CLIENT_SECRET"'"'"'
'

	[ "$status" -eq 0 ]
	[ "$output" = "xapi-client-id-marker:xapi-client-secret-marker" ]
	grep -q '^op <item> <get> <Hermes X API MCP> <--account> <my.1password.com> <--vault> <openclaw> <--format> <json>$' "$COMMAND_LOG"
	! grep -q 'xapi-client-secret-marker' "$COMMAND_LOG"
}

@test "syncs the X API refresh token into the local xurl cache before startup" {
	local xapi_lookup_count last_xapi_lookup up_line
	run_start_stack

	[ "$status" -eq 0 ]
	[ "$(stat -c '%a' "$HOME/.hermes/.xurl/auth.yml" 2>/dev/null || stat -f '%Lp' "$HOME/.hermes/.xurl/auth.yml")" = 600 ]
	grep -q 'client_id: "xapi-client-id-marker"' "$HOME/.hermes/.xurl/auth.yml"
	grep -q 'client_secret: "xapi-client-secret-marker"' "$HOME/.hermes/.xurl/auth.yml"
	grep -q 'refresh_token: "xapi-refresh-token-marker"' "$HOME/.hermes/.xurl/auth.yml"
	xapi_lookup_count="$(grep -c '<Hermes X API MCP>' "$COMMAND_LOG")"
	[ "$xapi_lookup_count" -ge 2 ]
	last_xapi_lookup="$(grep -n '<Hermes X API MCP>' "$COMMAND_LOG" | tail -n 1 | cut -d: -f1)"
	up_line="$(grep -n '<up> <-d> <--force-recreate> <hermes> <chromium> <browser-mcp> <xapi-mcp>' "$COMMAND_LOG" | cut -d: -f1)"
	[ "$last_xapi_lookup" -lt "$up_line" ]
	! grep -q 'xapi-refresh-token-marker' "$COMMAND_LOG"
}

@test "sync-token writes the local refresh token through the 1Password template" {
	mkdir -p "$HOME/.hermes/.xurl"
	cat >"$HOME/.hermes/.xurl/auth.yml" <<'EOF'
apps:
    default:
        oauth2_tokens:
            app-user:
                oauth2:
                    refresh_token: local-refresh-token-marker
default_app: default
EOF
	chmod 600 "$HOME/.hermes/.xurl/auth.yml"

	run env HERMES_COMPOSE_FILE="$REPO_ROOT/docker/hermes-agent/compose.yml" \
		bash "$REPO_ROOT/scripts/sh/hermes-xapi.sh" sync-token

	[ "$status" -eq 0 ]
	jq -e '.fields[] | select(.label == "X_API_REFRESH_TOKEN") | .value == "local-refresh-token-marker"' "$EDIT_CAPTURE" >/dev/null
	! grep -q 'local-refresh-token-marker' "$COMMAND_LOG"
}

@test "uses a mode-0600 cached service account after an op read timeout" {
	printf 'OP_SERVICE_ACCOUNT_TOKEN=cached-token\n' >"$HOME/.hermes/.op.env"
	chmod 600 "$HOME/.hermes/.op.env"
	export OP_READ_COMPLETION_FILE="$BATS_TEST_TMPDIR/op-read-completed"
	export OP_READ_DELAY_SECONDS=2 DOTFILES_HERMES_OP_READ_TIMEOUT_SECONDS=1
	run_start_stack
	[ "$status" -eq 0 ]
	[[ "$output" == *"using existing Hermes service-account environment"* ]]
	[ "$(cat "$HOME/.hermes/.op.env")" = 'OP_SERVICE_ACCOUNT_TOKEN=cached-token' ]
	[ "$(service_account_cache_mode)" = 600 ]
	/bin/sleep 2
	[ ! -e "$OP_READ_COMPLETION_FILE" ]
	[ "$(cat "$HOME/.hermes/.op.env")" = 'OP_SERVICE_ACCOUNT_TOKEN=cached-token' ]
	[ "$(service_account_cache_mode)" = 600 ]
}

@test "rejects a writable cached service account after an op read timeout" {
	printf 'OP_SERVICE_ACCOUNT_TOKEN=cached-token\n' >"$HOME/.hermes/.op.env"
	chmod 644 "$HOME/.hermes/.op.env"
	export OP_READ_DELAY_SECONDS=2 DOTFILES_HERMES_OP_READ_TIMEOUT_SECONDS=1
	run_start_stack
	[ "$status" -ne 0 ]
	! grep -q '^op' "$COMMAND_LOG"
	! grep -q '<compose>' "$COMMAND_LOG"
}

@test "rejects a symlinked cached service account before Compose" {
	printf 'OP_SERVICE_ACCOUNT_TOKEN=cached-token\n' >"$HOME/.hermes/cache-target"
	chmod 600 "$HOME/.hermes/cache-target"
	ln -s "$HOME/.hermes/cache-target" "$HOME/.hermes/.op.env"
	assert_service_account_cache_rejected_after_timeout
}

@test "rejects a directory cached service account before Compose" {
	mkdir "$HOME/.hermes/.op.env"
	assert_service_account_cache_rejected_after_timeout
}

@test "rejects an empty cached service account token after an op read timeout" {
	printf 'OP_SERVICE_ACCOUNT_TOKEN=\n' >"$HOME/.hermes/.op.env"
	chmod 600 "$HOME/.hermes/.op.env"
	assert_service_account_cache_rejected_after_timeout
}

@test "rejects an extra cached service account line after an op read timeout" {
	printf 'OP_SERVICE_ACCOUNT_TOKEN=cached-token\nOP_SERVICE_ACCOUNT_TOKEN=extra-token\n' >"$HOME/.hermes/.op.env"
	chmod 600 "$HOME/.hermes/.op.env"
	assert_service_account_cache_rejected_after_timeout
}

@test "rejects a malformed cached service account line after an op read timeout" {
	printf 'OP_SERVICE_ACCOUNT_TOKEN=cached-token\nnot-an-environment-assignment\n' >"$HOME/.hermes/.op.env"
	chmod 600 "$HOME/.hermes/.op.env"
	assert_service_account_cache_rejected_after_timeout
}

@test "defaults invalid service-account read timeouts to twenty seconds" {
	grep -Fq 'timeout_seconds="${DOTFILES_HERMES_OP_READ_TIMEOUT_SECONDS:-20}"' "$REPO_ROOT/scripts/sh/hermes-agent.sh"
	grep -Fq '[[ $timeout_seconds =~ ^([1-9]|[1-9][0-9]|[12][0-9]{2}|300)$ ]] || timeout_seconds=20' "$REPO_ROOT/scripts/sh/hermes-agent.sh"
	export DOTFILES_HERMES_OP_READ_TIMEOUT_SECONDS=invalid
	run_start_stack
	[ "$status" -eq 0 ]
}

@test "defaults service-account read timeouts above 300 seconds to twenty seconds" {
	grep -Fq '[[ $timeout_seconds =~ ^([1-9]|[1-9][0-9]|[12][0-9]{2}|300)$ ]] || timeout_seconds=20' "$REPO_ROOT/scripts/sh/hermes-agent.sh"
	export DOTFILES_HERMES_OP_READ_TIMEOUT_SECONDS=301
	run_start_stack
	[ "$status" -eq 0 ]
}

@test "defaults arbitrarily large service-account read timeouts to twenty seconds" {
	export DOTFILES_HERMES_OP_READ_TIMEOUT_SECONDS=999999999999999999999999999999999999
	run bash -c '
set -euo pipefail
. "$REPO_ROOT/scripts/sh/install-common.sh"
. "$REPO_ROOT/scripts/sh/hermes-agent.sh"
dotfiles_hermes_service_account_read_timeout_seconds
'
	[ "$status" -eq 0 ]
	[ "$output" = 20 ]
}

@test "atomically replaces an old service account cache after a successful op read" {
	printf 'OP_SERVICE_ACCOUNT_TOKEN=old-token\n' >"$HOME/.hermes/.op.env"
	chmod 600 "$HOME/.hermes/.op.env"
	ln "$HOME/.hermes/.op.env" "$HOME/.hermes/.op.env.previous"
	export OP_READ_TOKEN='fresh-token'
	run_start_stack
	[ "$status" -eq 0 ]
	[ "$(cat "$HOME/.hermes/.op.env")" = 'OP_SERVICE_ACCOUNT_TOKEN=fresh-token' ]
	[ "$(service_account_cache_mode)" = 600 ]
	[ "$(cat "$HOME/.hermes/.op.env.previous")" = 'OP_SERVICE_ACCOUNT_TOKEN=old-token' ]
	[ "$(service_account_cache_inode "$HOME/.hermes/.op.env")" != "$(service_account_cache_inode "$HOME/.hermes/.op.env.previous")" ]
	[ -z "$(find "$HOME/.hermes" -maxdepth 1 -name '.op.env.*' ! -name '.op.env.previous' -print -quit)" ]
}

@test "preserves the old service account cache when fresh replacement cannot be staged" {
	printf 'OP_SERVICE_ACCOUNT_TOKEN=old-token\n' >"$HOME/.hermes/.op.env"
	chmod 600 "$HOME/.hermes/.op.env"
	write_stub mktemp '
case "${1:-}" in
  *.op.read.XXXXXX) exec /usr/bin/mktemp "$@" ;;
  *) exit 1 ;;
esac
'
	export OP_READ_TOKEN='fresh-token'
	run_start_stack
	status=$status
	output=$output
	[ "$status" -ne 0 ]
	! grep -q '<compose>' "$COMMAND_LOG"
	[ "$(cat "$HOME/.hermes/.op.env")" = 'OP_SERVICE_ACCOUNT_TOKEN=old-token' ]
	[ "$(service_account_cache_mode)" = 600 ]
}

@test "fails preflight before Compose when op is unavailable" {
	run_start_stack op

	[ "$status" -ne 0 ]
	[[ "$output" == *"1Password CLI (op) is required"* ]]
	[ ! -s "$COMMAND_LOG" ]
}

@test "fails preflight before Compose when jq is unavailable" {
	run_start_stack jq

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
	export PLAN_JSON='{"schema_version":1,"items":[{"key":"dashboard","account":"my.1password.com","vault":"openclaw","item":"Hermes Agent Dashboard","fields":[]},{"key":"github","account":"my.1password.com","vault":"openclaw","item":"GitHubUsedOpenClawPAT","fields":[]},{"key":"discord_default","account":"my.1password.com","vault":"openclaw","item":"Master","fields":[]},{"key":"discord_rick","account":"my.1password.com","vault":"openclaw","item":"Rick","fields":[]},{"key":"discord_hoffman","account":"my.1password.com","vault":"openclaw","item":"Hoffman","fields":[]},{"key":"discord_risarisa","account":"my.1password.com","vault":"openclaw","item":"RisaRisa","fields":[]}]}'
	assert_plan_rejected_before_secret_lookup

	export PLAN_JSON='{"schema_version":1,"items":[{"key":"dashboard","account":"my.1password.com","vault":"openclaw","item":"Hermes Agent Dashboard","fields":[{"canonical_name":"username","labels":["username"]}]},{"key":"dashboard","account":"my.1password.com","vault":"openclaw","item":"GitHubUsedOpenClawPAT","fields":[{"canonical_name":"credential","labels":["credential"]}]},{"key":"discord_default","account":"my.1password.com","vault":"openclaw","item":"Master","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]}]},{"key":"discord_rick","account":"my.1password.com","vault":"openclaw","item":"Rick","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]}]},{"key":"discord_hoffman","account":"my.1password.com","vault":"openclaw","item":"Hoffman","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]}]},{"key":"discord_risarisa","account":"my.1password.com","vault":"openclaw","item":"RisaRisa","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]}]}]}'
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
	export OP_FAIL_ITEM='Rick'
	export BOOTSTRAP_STATUS=2

	run_start_stack

	[ "$status" -eq 1 ]
	grep -q '<Rick>' "$COMMAND_LOG"
	grep -q '<apply>' "$COMMAND_LOG"
	! grep -q '<up> <-d> <--force-recreate>' "$COMMAND_LOG"
	! grep -q '"type":"end"' "$PAYLOAD_CAPTURE"
	if grep -q "$SECRET_MARKER" "$COMMAND_LOG"; then
		false
	fi
	[[ "$output" != *"$SECRET_MARKER"* ]]
}

@test "recovers the existing Hermes runtime while preserving bootstrap migration exit five" {
	export BOOTSTRAP_STATUS=5

	run_start_stack

	[ "$status" -eq 5 ]
	grep -q '<apply>' "$COMMAND_LOG"
	assert_log_order '<up> <-d> <hindsight>' '<ps> <--all> <--services> <hermes>' '<stop> <hermes>' '<apply>' '<start>' '<http://127.0.0.1:8642/health>'
	[ "$(cat "$READY_ATTEMPT_FILE")" -eq 1 ]
	! grep -q '<up> <-d> <--force-recreate>' "$COMMAND_LOG"
	! grep -q '<Hermes X API MCP>' "$COMMAND_LOG"
	! grep -q '<ps> <--all>$' "$COMMAND_LOG"
	! grep -q "$SECRET_MARKER" "$COMMAND_LOG"
	[[ "$output" != *"$SECRET_MARKER"* ]]
}

@test "preserves a typed bootstrap exit when the apply consumer closes stdin early" {
	export BOOTSTRAP_STATUS=3
	export BOOTSTRAP_EXIT_EARLY=1
	export OP_DELAY_SECONDS=0.1

	run_start_stack

	[ "$status" -eq 3 ]
	grep -q '<apply>' "$COMMAND_LOG"
	assert_log_order '<ps> <--all> <--services> <hermes>' '<stop> <hermes>' '<apply>' '<start>' '<http://127.0.0.1:8642/health>'
	[ "$(cat "$READY_ATTEMPT_FILE")" -eq 1 ]
	! grep -q '<up> <-d> <--force-recreate>' "$COMMAND_LOG"
	! grep -q '<Hermes X API MCP>' "$COMMAND_LOG"
	! grep -q '<ps> <--all>$' "$COMMAND_LOG"
	[[ "$output" != *"$SECRET_MARKER"* ]]
}

@test "does not create a Hermes runtime after bootstrap failure when none existed" {
	export BOOTSTRAP_STATUS=5
	export HERMES_RUNTIME_EXISTS=0

	run_start_stack

	[ "$status" -eq 5 ]
	grep -q '<ps> <--all> <--services> <hermes>' "$COMMAND_LOG"
	grep -q '<ps> <--all>$' "$COMMAND_LOG"
	! grep -q '<start>' "$COMMAND_LOG"
	! grep -q '<up>' "$COMMAND_LOG"
	[ "$(cat "$READY_ATTEMPT_FILE")" -eq 0 ]
}

@test "recovers the existing Hermes runtime when recreated stack startup fails" {
	export UP_STATUS=42

	run_start_stack

	[ "$status" -eq 42 ]
	assert_log_order '<stop> <hermes>' '<apply>' '<up> <-d> <--force-recreate>' '<start>' '<http://127.0.0.1:8642/health>'
}

@test "does not expose secret payload records when the caller enables xtrace" {
	run env DOTFILES_TEST_MISSING_COMMAND="" bash -x -c '
set -euo pipefail
. "$REPO_ROOT/scripts/sh/install-common.sh"
. "$REPO_ROOT/scripts/sh/hermes-agent.sh"
dotfiles_hermes_start_stack docker "$COMPOSE_FILE"
'

	[ "$status" -eq 0 ]
	grep -q "$SECRET_MARKER" "$PAYLOAD_CAPTURE"
	[[ "$output" != *"$SECRET_MARKER"* ]]
}

@test "streams an ordered versioned payload and recreates services after success" {
	run_start_stack

	[ "$status" -eq 0 ]
	assert_log_order '<config> <--quiet>' '<http://127.0.0.1:11434/api/version>' '^ollama <pull> <qwen3.6:35b>' '^ollama <pull> <qwen3-embedding:0.6b>' '<http://127.0.0.1:11434/api/tags>' '<up> <-d> <hindsight>' '<http://127.0.0.1:8888/health>' '<build> <--pull> <hermes> <hermes-bootstrap> <chromium> <xapi-mcp>' '<stop> <hermes>' '<secret-plan>' '<apply>' '<Hermes Agent Dashboard>' '<GitHubUsedOpenClawPAT>' '<Google Calendar MCP>' '<Master>' '<Rick>' '<Hoffman>' '<RisaRisa>' '<Nancy>' '<Kuroda>' '<Shiraishi>' '<Hermes X API MCP>' '<up> <-d> <--force-recreate> <hermes> <chromium> <browser-mcp> <xapi-mcp>' '<http://127.0.0.1:8642/health>' '<image> <prune> <--force>'
	mapfile -t records < <("$REAL_JQ" -r '.type + ":" + (.key // "")' "$PAYLOAD_CAPTURE")
	[ "${records[*]}" = 'header: item:dashboard item:github item:google_calendar item:discord_default item:discord_rick item:discord_hoffman item:discord_risarisa item:discord_nancy item:discord_kuroda item:discord_shiraishi end:' ]
	"$REAL_JQ" -e -c 'select(.type == "item") | .item.id == "item-id"' "$PAYLOAD_CAPTURE" >/dev/null
	! grep -q "$SECRET_MARKER" "$COMMAND_LOG"
	[[ "$output" != *"$SECRET_MARKER"* ]]
}

@test "fails clearly when native Ollama is unavailable before building Hermes" {
	run_start_stack ollama

	[ "$status" -ne 0 ]
	[[ "$output" == *"ollama is required"* ]]
	! grep -q '<build>' "$COMMAND_LOG"
}

@test "Linux resolves the native Ollama endpoint from the Docker bridge" {
	unset HINDSIGHT_OLLAMA_URL
	write_stub uname 'printf "Linux\n"'
	docker_gateway() {
		[ "$*" = "network inspect bridge --format {{(index .IPAM.Config 0).Gateway}}" ]
		printf '172.19.0.1\n'
	}
	. "$REPO_ROOT/scripts/sh/install-common.sh"
	. "$REPO_ROOT/scripts/sh/hermes-hindsight.sh"

	dotfiles_hermes_hindsight_configure_ollama_url docker_gateway

	[ "$HINDSIGHT_OLLAMA_URL" = "http://172.19.0.1:11434" ]
}

@test "configured Ollama URL is propagated to native model pulls" {
	export HINDSIGHT_OLLAMA_URL=http://172.19.0.1:11434
	OLLAMA_HOST_CAPTURE="$BATS_TEST_TMPDIR/ollama-hosts"
	export OLLAMA_HOST_CAPTURE
	write_stub ollama '
printf "%s\n" "${OLLAMA_HOST:-}" >>"$OLLAMA_HOST_CAPTURE"
'

	run_start_stack

	[ "$status" -eq 0 ]
	[ "$(sort -u "$OLLAMA_HOST_CAPTURE")" = "172.19.0.1:11434" ]
}

@test "fails clearly when native Ollama is unreachable before pulling models" {
	export OLLAMA_READY_AFTER=99 HINDSIGHT_OLLAMA_READY_ATTEMPTS=3

	run_start_stack

	[ "$status" -ne 0 ]
	[[ "$output" == *"Ollama API did not become ready after 3 attempts."* ]]
	[ "$(cat "$OLLAMA_READY_ATTEMPT_FILE")" -eq 3 ]
	! grep -q '^ollama ' "$COMMAND_LOG"
	! grep -q '<build>' "$COMMAND_LOG"
}

@test "provisions exactly the two configured Ollama models and persistent Hindsight data before bootstrap" {
	run_start_stack

	[ "$status" -eq 0 ]
	[ "$(grep -c '^ollama <pull>' "$COMMAND_LOG")" -eq 2 ]
	grep -Fxq 'ollama <pull> <qwen3.6:35b>' "$COMMAND_LOG"
	grep -Fxq 'ollama <pull> <qwen3-embedding:0.6b>' "$COMMAND_LOG"
	[ -d "$HOME/.hermes/hindsight/pg0" ]
	[ -d "$HOME/.hermes/hindsight/cache" ]
	! grep -q '^ollama <serve>' "$COMMAND_LOG"
	! grep -q '^ollama <start>' "$COMMAND_LOG"
	! grep -q '<build>.*<hindsight>' "$COMMAND_LOG"
	full_stack_start="$(grep '<up> <-d> <--force-recreate>' "$COMMAND_LOG")"
	[[ "$full_stack_start" == *'<hermes> <chromium> <browser-mcp> <xapi-mcp>'* ]]
	[[ "$full_stack_start" != *'<hindsight>'* ]]
	[[ "$full_stack_start" != *'<--wait>'* ]]
}

@test "explicit Hindsight executables override PATH lookup" {
	export DOTFILES_HERMES_OLLAMA_EXECUTABLE="$STUB_BIN/ollama"
	export DOTFILES_HERMES_CURL_EXECUTABLE="$STUB_BIN/curl"

	run_start_stack

	[ "$status" -eq 0 ]
	grep -Fq "timeout <--foreground> <--kill-after=30> <3600> <$STUB_BIN/ollama> <pull> <qwen3.6:35b>" \
		"$COMMAND_LOG"
	run bash -c '. "$REPO_ROOT/scripts/sh/install-common.sh"; . "$REPO_ROOT/scripts/sh/hermes-hindsight.sh"; dotfiles_hermes_hindsight_curl_command'
	[ "$status" -eq 0 ]
	[ "$output" = "$STUB_BIN/curl" ]
}

@test "bounds Ollama model pulls with the default 3600 second GNU timeout" {
	unset HINDSIGHT_OLLAMA_PULL_TIMEOUT_SECONDS

	run_start_stack

	[ "$status" -eq 0 ]
	[ "$(grep -c '^timeout <--foreground> <--kill-after=30> <3600> <ollama> <pull>' "$COMMAND_LOG")" -eq 2 ]
}

@test "honors the Ollama model pull timeout override" {
	export HINDSIGHT_OLLAMA_PULL_TIMEOUT_SECONDS=7200

	run_start_stack

	[ "$status" -eq 0 ]
	[ "$(grep -c '^timeout <--foreground> <--kill-after=30> <7200> <ollama> <pull>' "$COMMAND_LOG")" -eq 2 ]
}

@test "propagates an Ollama model pull timeout without starting Hindsight" {
	export OLLAMA_PULL_TIMEOUT_STATUS=124

	run_start_stack

	[ "$status" -eq 124 ]
	! grep -q '<up> <-d> <hindsight>' "$COMMAND_LOG"
}

@test "fails clearly when GNU timeout is unavailable" {
	run_start_stack timeout

	[ "$status" -ne 0 ]
	[[ "$output" == *"GNU timeout is required for Hermes Hindsight model pulls."* ]]
	! grep -q '^ollama <pull>' "$COMMAND_LOG"
}

@test "propagates a configured Ollama model pull failure without starting Hindsight or Hermes" {
	export OLLAMA_PULL_FAILURE='qwen3-embedding:0.6b'

	run_start_stack

	[ "$status" -eq 42 ]
	grep -Fxq 'ollama <pull> <qwen3.6:35b>' "$COMMAND_LOG"
	grep -Fxq 'ollama <pull> <qwen3-embedding:0.6b>' "$COMMAND_LOG"
	! grep -q '<up> <-d> <hindsight>' "$COMMAND_LOG"
	! grep -q '<build>' "$COMMAND_LOG"
}

@test "requires Hindsight database connectivity before the Hermes bootstrap" {
	export HINDSIGHT_API_DATABASE=disconnected HINDSIGHT_API_READY_ATTEMPTS=1

	run_start_stack

	[ "$status" -ne 0 ]
	[[ "$output" == *"Hindsight API did not become ready after 1 attempts."* ]]
	grep -q '<up> <-d> <hindsight>' "$COMMAND_LOG"
	! grep -q '<build>' "$COMMAND_LOG"
}

@test "default Hindsight readiness succeeds on the 150th attempt" {
	unset HINDSIGHT_API_READY_ATTEMPTS HINDSIGHT_API_READY_DELAY_SECONDS
	export HINDSIGHT_API_READY_AFTER=150

	run bash -c '
set -euo pipefail
. "$REPO_ROOT/scripts/sh/install-common.sh"
. "$REPO_ROOT/scripts/sh/hermes-agent.sh"
dotfiles_hermes_hindsight_wait_for_api
'

	[ "$status" -eq 0 ]
	[ "$(cat "$HINDSIGHT_READY_ATTEMPT_FILE")" -eq 150 ]
	[ "$(grep -c '^sleep <2>$' "$COMMAND_LOG")" -eq 149 ]
}

@test "parses only one nonempty exact Hindsight environment assignment without evaluation" {
	printf '%s\n' \
		'HINDSIGHT_API_LLM_MODEL=$(touch should-not-exist)' \
		'HINDSIGHT_API_EMBEDDINGS_OPENAI_MODEL=qwen3-embedding:0.6b' >"$BATS_TEST_TMPDIR/hindsight.env"

	run bash -c '
set -euo pipefail
. "$REPO_ROOT/scripts/sh/install-common.sh"
. "$REPO_ROOT/scripts/sh/hermes-agent.sh"
dotfiles_hermes_hindsight_env_value "$COMPOSE_FILE" HINDSIGHT_API_LLM_MODEL
'

	[ "$status" -eq 0 ]
	[ "$output" = '$(touch should-not-exist)' ]
	[ ! -e "$BATS_TEST_TMPDIR/should-not-exist" ]
	printf '%s\n' \
		'HINDSIGHT_API_LLM_MODEL=qwen3.6:35b' \
		'HINDSIGHT_API_LLM_MODEL=duplicate' >"$BATS_TEST_TMPDIR/hindsight.env"
	run bash -c '. "$REPO_ROOT/scripts/sh/install-common.sh"; . "$REPO_ROOT/scripts/sh/hermes-agent.sh"; dotfiles_hermes_hindsight_env_value "$COMPOSE_FILE" HINDSIGHT_API_LLM_MODEL'
	[ "$status" -ne 0 ]
	printf '%s\n' 'HINDSIGHT_API_LLM_MODEL=' >"$BATS_TEST_TMPDIR/hindsight.env"
	run bash -c '. "$REPO_ROOT/scripts/sh/install-common.sh"; . "$REPO_ROOT/scripts/sh/hermes-agent.sh"; dotfiles_hermes_hindsight_env_value "$COMPOSE_FILE" HINDSIGHT_API_LLM_MODEL'
	[ "$status" -ne 0 ]
}

@test "waits for the Hermes API to become ready before reporting success" {
	export API_READY_AFTER=3

	run_start_stack

	[ "$status" -eq 0 ]
	[ "$(cat "$READY_ATTEMPT_FILE")" -eq 3 ]
	[ "$(grep -c '<http://127.0.0.1:8642/health>' "$COMMAND_LOG")" -eq 3 ]
	grep -q '<http://127.0.0.1:8642/health>' "$COMMAND_LOG"
	[ "$(grep -c '^sleep <0>$' "$COMMAND_LOG")" -eq 2 ]
	assert_log_order '<up> <-d> <--force-recreate>' '<http://127.0.0.1:8642/health>' '<image> <prune> <--force>'
	if grep -q "$SECRET_MARKER" "$COMMAND_LOG"; then
		false
	fi
	[[ "$output" != *"$SECRET_MARKER"* ]]
}

@test "keeps successful Hermes activation when dangling image cleanup fails" {
	export IMAGE_PRUNE_STATUS=1

	run_start_stack

	[ "$status" -eq 0 ]
	grep -q '<image> <prune> <--force>' "$COMMAND_LOG"
	[[ "$output" == *"Warning: unable to remove dangling Docker images."* ]]
}

@test "fails after bounded Hermes API readiness attempts with redacted diagnostics" {
	export API_READY_AFTER=99
	export HERMES_API_READY_ATTEMPTS=3

	run_start_stack

	[ "$status" -ne 0 ]
	[ "$(cat "$READY_ATTEMPT_FILE")" -eq 3 ]
	[ "$(grep -c '^sleep <0>$' "$COMMAND_LOG")" -eq 2 ]
	grep -q '<ps> <--all>' "$COMMAND_LOG"
	! grep -q '<image> <prune> <--force>' "$COMMAND_LOG"
	[[ "$output" == *"Hermes API did not become ready after 3 attempts."* ]]
	if grep -q "$SECRET_MARKER" "$COMMAND_LOG"; then
		false
	fi
	[[ "$output" != *"$SECRET_MARKER"* ]]
}

@test "forwards Docker calls through a function runner and retains host runtime paths" {
	run_start_stack_with_function_runner

	[ "$status" -eq 0 ]
	grep -q '^runner <compose> <-f> <' "$COMMAND_LOG"
	[ -d "$TEST_HOME/.hermes/.xurl" ]
	[ -d "$TEST_HOME/.hermes/.browser" ]
}

@test "removes host writers for dashboard messaging model profile and env content" {
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
