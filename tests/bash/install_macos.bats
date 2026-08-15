#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	INSTALLER="$REPO_ROOT/scripts/sh/install-macos.sh"
	COMMON_INSTALLER="$REPO_ROOT/scripts/sh/install-common.sh"
	HERMES_INSTALLER="$REPO_ROOT/scripts/sh/hermes-agent.sh"
	TEST_HOME="$BATS_TEST_TMPDIR/home"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"
	PAYLOAD_CAPTURE="$BATS_TEST_TMPDIR/payload.ndjson"
	FAKE_DOCKER_APP="$BATS_TEST_TMPDIR/Docker.app"
	FAKE_NIX_PROFILE="$BATS_TEST_TMPDIR/nix-daemon.sh"
	FAKE_BASHRC="$BATS_TEST_TMPDIR/etc/bashrc"
	FAKE_ZSHRC="$BATS_TEST_TMPDIR/etc/zshrc"
	FAKE_USER_PROFILE_ROOT="$BATS_TEST_TMPDIR/etc/profiles/per-user"
	TEST_HOMEBREW_CASK_PARENT_DIR="$BATS_TEST_TMPDIR/usr/local"
	TEST_HOMEBREW_CASK_BIN_DIR="$TEST_HOMEBREW_CASK_PARENT_DIR/bin"
	TEST_HOMEBREW_CASK_CLI_PLUGIN_DIR="$TEST_HOMEBREW_CASK_PARENT_DIR/cli-plugins"
	TEST_HOMEBREW_LINK_TARGET="$BATS_TEST_TMPDIR/link-target"
	FAKE_HOMEBREW_BIN_DIR="$TEST_HOMEBREW_CASK_BIN_DIR"
	FAKE_HOMEBREW_CLI_PLUGINS_DIR="$TEST_HOMEBREW_CASK_CLI_PLUGIN_DIR"
	REAL_JQ="$(command -v jq)"
	mkdir -p "$TEST_HOME" "$STUB_BIN" "$TEST_HOMEBREW_CASK_PARENT_DIR" "$TEST_HOMEBREW_LINK_TARGET"
	chmod 0755 "$TEST_HOMEBREW_CASK_PARENT_DIR"
	: >"$COMMAND_LOG"
	: >"$PAYLOAD_CAPTURE"
	: >"$FAKE_NIX_PROFILE"

	export HOME="$TEST_HOME"
	export USER="test-user"
	export SUDO_USER="test-user"
	export DOTFILES_USER="test-user"
	export PATH="$STUB_BIN:/usr/bin:/bin"
	export COMMAND_LOG STUB_BIN PAYLOAD_CAPTURE REAL_JQ INSTALLER
	export DOTFILES_SKIP_HERDR_INSTALL=1
	export FAKE_BASHRC FAKE_ZSHRC FAKE_DOCKER_APP
	export FAKE_HOMEBREW_BIN_DIR FAKE_HOMEBREW_CLI_PLUGINS_DIR
	export TEST_HOMEBREW_CASK_PARENT_DIR TEST_HOMEBREW_CASK_BIN_DIR
	export TEST_HOMEBREW_CASK_CLI_PLUGIN_DIR TEST_HOMEBREW_LINK_TARGET
	export HERMES_SECRET_PLAN="$(valid_secret_plan)"
	export HERMES_ITEM_JSON='{"id":"fixture-item","fields":[]}'
	export HERMES_XAPI_ITEM_JSON='{"id":"xapi-item","fields":[{"label":"X_API_CLIENT_ID","value":"xapi-client-id-marker"},{"label":"X_API_CLIENT_SECRET","value":"xapi-client-secret-marker"}]}'
	export HERMES_BOOTSTRAP_STATUS=0
	export DOTFILES_DOCKER_APP_PATH="$FAKE_DOCKER_APP"
	export DOTFILES_DOCKER_SETUP_MARKER="$TEST_HOME/.config/dotfiles/docker-desktop-installed"
	export DOTFILES_NIX_PROFILE_SCRIPT="$FAKE_NIX_PROFILE"
	export DOTFILES_BASHRC_PATH="$FAKE_BASHRC"
	export DOTFILES_ZSHRC_PATH="$FAKE_ZSHRC"
	export DOTFILES_USER_PROFILE_ROOT="$FAKE_USER_PROFILE_ROOT"
	export DOTFILES_HOMEBREW_BIN_DIR="$FAKE_HOMEBREW_BIN_DIR"
	export DOTFILES_HOMEBREW_CLI_PLUGINS_DIR="$FAKE_HOMEBREW_CLI_PLUGINS_DIR"
	export DOTFILES_DOCKER_WAIT_ATTEMPTS=2
	export DOTFILES_WAIT_SLEEP_SECONDS=0
	export DOTFILES_VERIFY_ENVIRONMENT="$STUB_BIN/verify-environment"
	export DOTFILES_HOMEBREW_CASK_UPDATER="$STUB_BIN/update-homebrew-casks"
	export DOTFILES_HOMEBREW_CASK_BIN_DIR="$BATS_TEST_TMPDIR/untrusted/bin"
	export DOTFILES_HOMEBREW_CASK_CLI_PLUGIN_DIR="$BATS_TEST_TMPDIR/untrusted/cli-plugins"
	export HOMEBREW_CASK_UPDATE_STATUS=0
	export TEST_HOMEBREW_PARENT_METADATA='0 755'
	export TEST_HOMEBREW_PARENT_ACL_STATE=absent
	export TEST_HOMEBREW_PARENT_IMMUTABLE_TO_CALLER=1
	export SUDO_FAIL_OPERATION=''
	export SUDO_FAILURE_STATUS=47
	export SUDO_SWAP_CLI_PLUGIN_TARGET=0

	write_stub uname '
case "${1:-}" in
	-s) echo Darwin ;;
	-m) echo arm64 ;;
	*) exit 2 ;;
esac
'
	write_stub sw_vers '
[ "${1:-}" = "-productVersion" ] && echo 26.5.1
'
	write_stub xcode-select '
[ "${1:-}" = "-p" ] && { echo /Library/Developer/CommandLineTools; exit 0; }
exit 2
'
	write_stub nc 'exit 0'
	write_stub curl '
printf "curl %s\n" "$*" >>"$COMMAND_LOG"
case "$*" in
  *"/api/tags"*) printf "%s\n" "{\"models\":[{\"name\":\"qwen3.6:35b\"},{\"name\":\"qwen3-embedding:0.6b\"}]}" ;;
  *"127.0.0.1:8888/health"*) printf "%s\n" "{\"status\":\"healthy\",\"database\":\"connected\"}" ;;
esac
exit 0
'
	write_stub ollama 'printf "ollama %s\n" "$*" >>"$COMMAND_LOG"'
	write_stub pgrep '
printf "pgrep %s\n" "$*" >>"$COMMAND_LOG"
exit 0
'
	write_stub sleep 'exit 0'
	write_stub date 'echo 20260717010203'
	write_stub sudo '
printf "sudo" >>"$COMMAND_LOG"
printf " <%s>" "$@" >>"$COMMAND_LOG"
printf "\n" >>"$COMMAND_LOG"
is_allowed_cask_target() {
	[[ $1 == /usr/local/bin || $1 == /usr/local/cli-plugins ||
		$1 == "$TEST_HOMEBREW_CASK_BIN_DIR" || $1 == "$TEST_HOMEBREW_CASK_CLI_PLUGIN_DIR" ]]
}
fixture_user="${DOTFILES_USER:-${SUDO_USER:-$USER}}"
fail_operation() {
	[[ ${SUDO_FAIL_OPERATION:-} != "$1" ]] || exit "$SUDO_FAILURE_STATUS"
}
case "${1:-}" in
	/bin/mkdir)
		if [[ $# -eq 3 && ${2:-} == -- ]] && is_allowed_cask_target "${3:-}"; then
			fail_operation mkdir
			if [[ ${SUDO_SWAP_CLI_PLUGIN_TARGET:-0} == 1 && ${3:-} == "$TEST_HOMEBREW_CASK_BIN_DIR" ]]; then
				ln -s "$TEST_HOMEBREW_LINK_TARGET" "$TEST_HOMEBREW_CASK_CLI_PLUGIN_DIR"
			fi
			exit 0
		fi
		;;
	/usr/sbin/chown)
		if [[ $# -eq 3 && ${2:-} == "$fixture_user:admin" ]] && is_allowed_cask_target "${3:-}"; then
			fail_operation chown
			exit 0
		fi
		;;
	/bin/chmod)
		if [[ $# -eq 3 && ${2:-} == 0775 ]] && is_allowed_cask_target "${3:-}"; then
			fail_operation chmod
			exit 0
		fi
		;;
	/bin/ln)
		if [[ $# -eq 4 && ${2:-} == -s && ${3:-} == /sbin/md5 && ${4:-} == /usr/local/bin/md5 ]]; then
			exit 0
		fi
		;;
	/usr/bin/env)
		if [[ $# -eq 13 && ${2:-} == "NIX_CONFIG=extra-experimental-features = nix-command flakes" &&
			${3:-} == "DOTFILES_USER=$fixture_user" && ${4:-} == "DOTFILES_HOME=$HOME" &&
			${5:-} == "DOTFILES_ROOT=$DOTFILES_ROOT" && ${6:-} == "$STUB_BIN/nix" &&
			${7:-} == run && ${8:-} == ".#darwin-rebuild" && ${9:-} == -- &&
			${10:-} == switch && ${11:-} == --flake && ${12:-} == ".#macos" && ${13:-} == --impure ]]; then
			exec "$@"
		fi
		;;
	mv)
		if [[ $# -eq 3 &&
			( ${2:-} == "$FAKE_BASHRC" || ${2:-} == "$FAKE_ZSHRC" ) &&
			${3:-} == "${2:-}.before-nix-darwin" ]]; then
			exec "$@"
		fi
		;;
	"$FAKE_DOCKER_APP/Contents/MacOS/install")
		if [[ $# -eq 3 && ${2:-} == --accept-license && ${3:-} == "--user=$fixture_user" ]]; then
			exec "$@"
		fi
		;;
esac
printf "Unexpected sudo argv:" >&2
printf " <%s>" "$@" >&2
printf "\n" >&2
exit 97
'
	write_stub verify-environment 'printf "verify-environment %s\n" "$*" >>"$COMMAND_LOG"'
	write_stub update-homebrew-casks '
printf "update-homebrew-casks %s\n" "$*" >>"$COMMAND_LOG"
exit "$HOMEBREW_CASK_UPDATE_STATUS"
'
	write_stub jq 'exec "$REAL_JQ" "$@"'
	write_stub op '
printf "op %s\n" "$*" >>"$COMMAND_LOG"
if [ "${3:-}" = "Hermes X API MCP" ]; then
	printf "%s\n" "$HERMES_XAPI_ITEM_JSON"
else
	printf "%s\n" "$HERMES_ITEM_JSON"
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

valid_secret_plan() {
	cat <<'JSON'
{"schema_version":1,"items":[{"key":"dashboard","account":"my.1password.com","vault":"openclaw","item":"Hermes Agent Dashboard","fields":[{"canonical_name":"username","labels":["username"]}]},{"key":"github","account":"my.1password.com","vault":"openclaw","item":"GitHubUsedOpenClawPAT","fields":[{"canonical_name":"credential","labels":["credential"]}]},{"key":"google_calendar","account":"my.1password.com","vault":"Private","item":"Google Calendar MCP","fields":[{"canonical_name":"oauth_credentials_json","labels":["oauth_credentials_json"]},{"canonical_name":"tokens_json","labels":["tokens_json"]}]},{"key":"discord_default","account":"my.1password.com","vault":"openclaw","item":"Master","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]}]},{"key":"discord_rick","account":"my.1password.com","vault":"openclaw","item":"Rick","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]}]},{"key":"discord_hoffman","account":"my.1password.com","vault":"openclaw","item":"Hoffman","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]}]},{"key":"discord_risarisa","account":"my.1password.com","vault":"openclaw","item":"RisaRisa","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]}]},{"key":"discord_nancy","account":"my.1password.com","vault":"openclaw","item":"Nancy","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]}]},{"key":"discord_kuroda","account":"my.1password.com","vault":"openclaw","item":"Kuroda","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]}]},{"key":"discord_shiraishi","account":"my.1password.com","vault":"openclaw","item":"Shiraishi","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]}]}]}
JSON
}

write_docker_app() {
	mkdir -p "$FAKE_DOCKER_APP/Contents/MacOS" "$FAKE_DOCKER_APP/Contents/Resources/bin"
	cat >"$FAKE_DOCKER_APP/Contents/MacOS/install" <<'EOF'
#!/usr/bin/env bash
printf 'docker-install %s\n' "$*" >>"$COMMAND_LOG"
EOF
	cat >"$FAKE_DOCKER_APP/Contents/Resources/bin/docker" <<'EOF'
#!/usr/bin/env bash
printf 'docker %s\n' "$*" >>"$COMMAND_LOG"
case " $* " in
  *" ps --all --services hermes "*) printf "hermes\n" ;;
  *" hermes-bootstrap secret-plan "*) printf '%s\n' "$HERMES_SECRET_PLAN" ;;
  *" hermes-bootstrap apply "*) cat >"$PAYLOAD_CAPTURE"; exit "$HERMES_BOOTSTRAP_STATUS" ;;
esac
EOF
	chmod +x \
		"$FAKE_DOCKER_APP/Contents/MacOS/install" \
		"$FAKE_DOCKER_APP/Contents/Resources/bin/docker"
}

write_installed_stubs() {
	write_docker_app
	mkdir -p "$FAKE_HOMEBREW_BIN_DIR" "$FAKE_HOMEBREW_CLI_PLUGINS_DIR"
	mkdir -p "$(dirname "$DOTFILES_DOCKER_SETUP_MARKER")"
	touch "$DOTFILES_DOCKER_SETUP_MARKER"

	write_stub nix 'printf "nix %s\n" "$*" >>"$COMMAND_LOG"'
	write_stub chezmoi 'printf "chezmoi %s\n" "$*" >>"$COMMAND_LOG"'
	write_stub docker '
printf "docker %s\n" "$*" >>"$COMMAND_LOG"
case " $* " in
  *" ps --all --services hermes "*) printf "hermes\n" ;;
  *" hermes-bootstrap secret-plan "*) printf "%s\n" "$HERMES_SECRET_PLAN" ;;
  *" hermes-bootstrap apply "*) cat >"$PAYLOAD_CAPTURE"; exit "$HERMES_BOOTSTRAP_STATUS" ;;
esac
'
	ln -s "$REPO_ROOT" "$HOME/.dotfiles"
}

write_fresh_install_stubs() {
	mkdir -p "$FAKE_HOMEBREW_BIN_DIR" "$FAKE_HOMEBREW_CLI_PLUGINS_DIR"
	write_stub curl '
printf "curl %s\n" "$*" >>"$COMMAND_LOG"
case "$*" in
	*"/api/version"*) exit 0 ;;
	*"/api/tags"*) printf "%s\n" "{\"models\":[{\"name\":\"qwen3.6:35b\"},{\"name\":\"qwen3-embedding:0.6b\"}]}"; exit 0 ;;
	*"127.0.0.1:8888/health"*) printf "%s\n" "{\"status\":\"healthy\",\"database\":\"connected\"}"; exit 0 ;;
	*/health*) exit 0 ;;
	*nixos.org/nix/install*)
		cat <<'"'"'SCRIPT'"'"'
printf "nix-installer %s\n" "$*" >>"$COMMAND_LOG"
cat >"$STUB_BIN/nix" <<'"'"'NIX'"'"'
#!/usr/bin/env bash
set -euo pipefail
printf "nix %s\n" "$*" >>"$COMMAND_LOG"
if [ "${1:-}" = "run" ]; then
	mkdir -p "$DOTFILES_DOCKER_APP_PATH/Contents/MacOS" "$DOTFILES_DOCKER_APP_PATH/Contents/Resources/bin"
		cat >"$DOTFILES_DOCKER_APP_PATH/Contents/MacOS/install" <<'"'"'DOCKER_INSTALL'"'"'
#!/usr/bin/env bash
printf "docker-install %s\n" "$*" >>"$COMMAND_LOG"
DOCKER_INSTALL
		cat >"$DOTFILES_DOCKER_APP_PATH/Contents/Resources/bin/docker" <<'"'"'DOCKER'"'"'
#!/usr/bin/env bash
printf "docker %s\n" "$*" >>"$COMMAND_LOG"
case " $* " in
  *" hermes-bootstrap secret-plan "*) printf "%s\n" "$HERMES_SECRET_PLAN" ;;
  *" hermes-bootstrap apply "*) cat >"$PAYLOAD_CAPTURE"; exit "$HERMES_BOOTSTRAP_STATUS" ;;
esac
DOCKER
	cat >"$STUB_BIN/chezmoi" <<'"'"'CHEZMOI'"'"'
#!/usr/bin/env bash
printf "chezmoi %s\n" "$*" >>"$COMMAND_LOG"
CHEZMOI
	chmod +x \
		"$DOTFILES_DOCKER_APP_PATH/Contents/MacOS/install" \
		"$DOTFILES_DOCKER_APP_PATH/Contents/Resources/bin/docker" \
		"$STUB_BIN/chezmoi"
fi
NIX
chmod +x "$STUB_BIN/nix"
SCRIPT
		;;
	*) exit 2 ;;
esac
'
}

assert_log_order() {
	local previous=0 pattern line
	for pattern in "$@"; do
		line="$(grep -nF "$pattern" "$COMMAND_LOG" | head -1 | cut -d: -f1)"
		[ -n "$line" ]
		[ "$line" -gt "$previous" ]
		previous="$line"
	done
}

@test "unsafe Homebrew cask link parent stops before privileged mutation" {
	local scenario expected
	for scenario in symlink wrong-owner writable; do
		if [[ -L $TEST_HOMEBREW_CASK_PARENT_DIR ]]; then
			rm "$TEST_HOMEBREW_CASK_PARENT_DIR"
		else
			rmdir "$TEST_HOMEBREW_CASK_PARENT_DIR"
		fi
		mkdir -p "$TEST_HOMEBREW_CASK_PARENT_DIR"
		chmod 0755 "$TEST_HOMEBREW_CASK_PARENT_DIR"
		export TEST_HOMEBREW_PARENT_METADATA='0 755'
		case "$scenario" in
		symlink)
			rmdir "$TEST_HOMEBREW_CASK_PARENT_DIR"
			ln -s "$TEST_HOMEBREW_LINK_TARGET" "$TEST_HOMEBREW_CASK_PARENT_DIR"
			expected="Refusing symbolic Homebrew cask link parent: $TEST_HOMEBREW_CASK_PARENT_DIR"
			;;
		wrong-owner)
			export TEST_HOMEBREW_PARENT_METADATA='501 755'
			expected="Homebrew cask link parent must be owned by root: $TEST_HOMEBREW_CASK_PARENT_DIR"
			;;
		writable)
			export TEST_HOMEBREW_PARENT_METADATA='0 775'
			expected="Homebrew cask link parent must not be group/other writable: $TEST_HOMEBREW_CASK_PARENT_DIR"
			;;
		esac
		: >"$COMMAND_LOG"

		run_test_homebrew_cask_link_convergence

		[ "$status" -ne 0 ]
		[[ "$output" == *"$expected"* ]]
		assert_no_homebrew_cask_link_mutations
		! grep -q '^update-homebrew-casks ' "$COMMAND_LOG"
	done
}

assert_no_homebrew_cask_link_mutations() {
	[ "$(grep -Ec '^sudo </bin/mkdir>|^sudo </usr/sbin/chown>|^sudo </bin/chmod>' "$COMMAND_LOG")" -eq 0 ]
}

reset_test_homebrew_cask_link_targets() {
	rm -f "$TEST_HOMEBREW_CASK_BIN_DIR" "$TEST_HOMEBREW_CASK_CLI_PLUGIN_DIR"
	: >"$COMMAND_LOG"
}

run_test_homebrew_cask_link_convergence() {
	run bash -c '
set -euo pipefail
. "$INSTALLER"
homebrew_cask_link_parent_metadata() {
  printf "%s\n" "$TEST_HOMEBREW_PARENT_METADATA"
}
homebrew_cask_link_parent_acl_state() {
  printf "%s\n" "$TEST_HOMEBREW_PARENT_ACL_STATE"
}
homebrew_cask_link_parent_is_immutable_to_caller() {
  [[ $TEST_HOMEBREW_PARENT_IMMUTABLE_TO_CALLER == 1 ]]
}
export DOTFILES_USER=test-user
ensure_homebrew_cask_link_directories_under_parent \
  "$TEST_HOMEBREW_CASK_PARENT_DIR" \
  "$TEST_HOMEBREW_CASK_BIN_DIR" \
  "$TEST_HOMEBREW_CASK_CLI_PLUGIN_DIR"
"$DOTFILES_HOMEBREW_CASK_UPDATER"
'
}

run_macos_installer_for_host() {
	shift

	run bash -c '
set -euo pipefail
. "$INSTALLER"
ensure_docker_desktop_md5_compatibility() {
  :
}
homebrew_cask_link_parent_metadata() {
  printf "%s\n" "$TEST_HOMEBREW_PARENT_METADATA"
}
homebrew_cask_link_parent_acl_state() {
  printf "%s\n" "$TEST_HOMEBREW_PARENT_ACL_STATE"
}
homebrew_cask_link_parent_is_immutable_to_caller() {
  [[ $TEST_HOMEBREW_PARENT_IMMUTABLE_TO_CALLER == 1 ]]
}
main "$@"
' bash "$@"
}

run_macos_installer() {
	run_macos_installer_for_host "$(/usr/bin/uname -s)" "$@"
}

@test "extended ACL grant on Homebrew cask link parent stops before privileged mutation" {
	export TEST_HOMEBREW_PARENT_ACL_STATE=present

	run_test_homebrew_cask_link_convergence

	[ "$status" -ne 0 ]
	[[ "$output" == *"Homebrew cask link parent must not have an extended ACL: $TEST_HOMEBREW_CASK_PARENT_DIR"* ]]
	assert_no_homebrew_cask_link_mutations
	! grep -q '^update-homebrew-casks ' "$COMMAND_LOG"
}

@test "caller-writable Homebrew cask link parent stops before privileged mutation" {
	export TEST_HOMEBREW_PARENT_IMMUTABLE_TO_CALLER=0

	run_test_homebrew_cask_link_convergence

	[ "$status" -ne 0 ]
	[[ "$output" == *"Homebrew cask link parent must not be writable by the current caller: $TEST_HOMEBREW_CASK_PARENT_DIR"* ]]
	assert_no_homebrew_cask_link_mutations
	! grep -q '^update-homebrew-casks ' "$COMMAND_LOG"
}

@test "installed prerequisites run nix-darwin chezmoi and Compose in order" {
	write_installed_stubs

	run_macos_installer

	[ "$status" -eq 0 ]
	grep -Fqx "sudo </usr/bin/env> <NIX_CONFIG=extra-experimental-features = nix-command flakes> <DOTFILES_USER=test-user> <DOTFILES_HOME=$TEST_HOME> <DOTFILES_ROOT=$REPO_ROOT> <$STUB_BIN/nix> <run> <.#darwin-rebuild> <--> <switch> <--flake> <.#macos> <--impure>" "$COMMAND_LOG"
	assert_log_order \
		"nix flake update --flake $REPO_ROOT" \
		"nix run .#darwin-rebuild -- switch --flake .#macos --impure" \
		"update-homebrew-casks " \
		"docker info" \
		"chezmoi init --source $REPO_ROOT/chezmoi" \
		"chezmoi apply --force" \
		"docker compose -f $REPO_ROOT/docker/hermes-agent/compose.yml config --quiet" \
		"docker compose -f $REPO_ROOT/docker/hermes-agent/compose.yml build --pull hermes hermes-bootstrap chromium xapi-mcp" \
		"docker compose -f $REPO_ROOT/docker/hermes-agent/compose.yml stop hermes" \
		"docker compose -f $REPO_ROOT/docker/hermes-agent/compose.yml run --rm --no-deps -T hermes-bootstrap secret-plan" \
		"docker compose -f $REPO_ROOT/docker/hermes-agent/compose.yml run --rm --no-deps -T hermes-bootstrap apply" \
		"docker compose -f $REPO_ROOT/docker/hermes-agent/compose.yml up -d --force-recreate" \
		"docker image prune --force" \
		"verify-environment --runtime"
	[ "$(grep -c '^op item get ' "$COMMAND_LOG")" -eq 11 ]
	[ "$(grep -c '^op signin --account my.1password.com$' "$COMMAND_LOG")" -eq 1 ]
	[ -s "$PAYLOAD_CAPTURE" ]
	! grep -q 'brew install --cask' "$COMMAND_LOG"
	! grep -q 'desktop.docker.com/mac' "$COMMAND_LOG"
	! grep -q 'docker-install' "$COMMAND_LOG"
}

@test "Docker Desktop md5 compatibility ensure uses fixed paths for all states" {
	write_docker_app

	run bash -c '
set -euo pipefail
. "$INSTALLER"
docker_desktop_md5_binary_is_executable() { return 1; }
ensure_docker_desktop_md5_compatibility
' bash

	[ "$status" -ne 0 ]
	[[ "$output" == *"macOS md5 executable is unavailable: /sbin/md5"* ]]

	: >"$COMMAND_LOG"
	run bash -c '
set -euo pipefail
. "$INSTALLER"
docker_desktop_md5_binary_is_executable() { :; }
docker_desktop_md5_link_state() {
  [[ $1 == /sbin/md5 && $2 == /usr/local/bin/md5 ]] || exit 91
  printf "expected-link\\n"
}
ensure_docker_desktop_md5_compatibility
' bash

	[ "$status" -eq 0 ]
	! grep -q '^sudo ' "$COMMAND_LOG"

	: >"$COMMAND_LOG"
	run bash -c '
set -euo pipefail
. "$INSTALLER"
docker_desktop_md5_binary_is_executable() { :; }
docker_desktop_md5_link_state() {
  [[ $1 == /sbin/md5 && $2 == /usr/local/bin/md5 ]] || exit 91
  printf "missing\\n"
}
ensure_docker_desktop_md5_compatibility
' bash

	[ "$status" -eq 0 ]
	[ "$(grep -Fxc 'sudo </bin/ln> <-s> </sbin/md5> </usr/local/bin/md5>' "$COMMAND_LOG")" -eq 1 ]
	[ "$(grep -c '^sudo ' "$COMMAND_LOG")" -eq 1 ]

	: >"$COMMAND_LOG"
	run bash -c '
set -euo pipefail
. "$INSTALLER"
docker_desktop_md5_binary_is_executable() { :; }
docker_desktop_md5_link_state() {
  [[ $1 == /sbin/md5 && $2 == /usr/local/bin/md5 ]] || exit 91
  printf "conflict\\n"
}
setup_docker_runtime
' bash

	[ "$status" -ne 0 ]
	[[ "$output" == *"Docker Desktop md5 compatibility path conflicts with existing entry: /usr/local/bin/md5"* ]]
	! grep -q '^sudo ' "$COMMAND_LOG"
	! grep -q '^docker-install ' "$COMMAND_LOG"
	! grep -q '^docker desktop start ' "$COMMAND_LOG"
}

@test "Docker Desktop md5 compatibility link state rejects a regular file without replacing it" {
	local path="$BATS_TEST_TMPDIR/md5"
	touch "$path"

	run bash -c '
set -euo pipefail
. "$INSTALLER"
docker_desktop_md5_link_state /sbin/md5 "$1"
' bash "$path"

	[ "$status" -eq 0 ]
	[ "$output" = conflict ]
	[ -f "$path" ]
}

@test "Docker Desktop md5 compatibility link state rejects a link to an existing different target" {
	local path="$BATS_TEST_TMPDIR/md5" target="$BATS_TEST_TMPDIR/other-md5"
	touch "$target"
	ln -s "$target" "$path"

	run bash -c '
set -euo pipefail
. "$INSTALLER"
docker_desktop_md5_link_state /sbin/md5 "$1"
' bash "$path"

	[ "$status" -eq 0 ]
	[ "$output" = conflict ]
	[ -L "$path" ]
	[ "$(/usr/bin/readlink "$path")" = "$target" ]
}

@test "Docker Desktop md5 compatibility link state rejects a dangling link without replacing it" {
	local path="$BATS_TEST_TMPDIR/md5" target="$BATS_TEST_TMPDIR/missing-md5"
	ln -s "$target" "$path"

	run bash -c '
set -euo pipefail
. "$INSTALLER"
docker_desktop_md5_link_state /sbin/md5 "$1"
' bash "$path"

	[ "$status" -eq 0 ]
	[ "$output" = conflict ]
	[ -L "$path" ]
	[ "$(/usr/bin/readlink "$path")" = "$target" ]
}

@test "macOS installer accepts the sudo user for cask directory repair" {
	local runner_user="runner"
	write_installed_stubs

	export SUDO_USER="$runner_user"
	export DOTFILES_USER="$runner_user"
	run_macos_installer

	[ "$status" -eq 0 ]
	grep -Fqx "sudo </usr/sbin/chown> <$runner_user:admin> </usr/local/bin>" "$COMMAND_LOG"
	grep -Fqx "sudo </usr/sbin/chown> <$runner_user:admin> </usr/local/cli-plugins>" "$COMMAND_LOG"
}

@test "production Homebrew cask link directories are fixed before cask updates" {
	write_installed_stubs
	local expected_sudo_count=9 target

	run_macos_installer

	[ "$status" -eq 0 ]
	grep -Fqx "sudo </usr/bin/env> <NIX_CONFIG=extra-experimental-features = nix-command flakes> <DOTFILES_USER=test-user> <DOTFILES_HOME=$TEST_HOME> <DOTFILES_ROOT=$REPO_ROOT> <$STUB_BIN/nix> <run> <.#darwin-rebuild> <--> <switch> <--flake> <.#macos> <--impure>" "$COMMAND_LOG"
	! grep -Fq "$DOTFILES_HOMEBREW_CASK_BIN_DIR" "$COMMAND_LOG"
	! grep -Fq "$DOTFILES_HOMEBREW_CASK_CLI_PLUGIN_DIR" "$COMMAND_LOG"
	[ "$(grep -Fxc 'sudo </usr/sbin/chown> <test-user:admin> </usr/local/bin>' "$COMMAND_LOG")" -eq 1 ]
	[ "$(grep -Fxc 'sudo </bin/chmod> <0775> </usr/local/bin>' "$COMMAND_LOG")" -eq 1 ]
	[ "$(grep -Fxc 'sudo </usr/sbin/chown> <test-user:admin> </usr/local/cli-plugins>' "$COMMAND_LOG")" -eq 1 ]
	[ "$(grep -Fxc 'sudo </bin/chmod> <0775> </usr/local/cli-plugins>' "$COMMAND_LOG")" -eq 1 ]
	! grep -Fq 'sudo </bin/mkdir> <-p>' "$COMMAND_LOG"
	for target in /usr/local/bin /usr/local/cli-plugins; do
		if [[ ! -e $target ]]; then
			[ "$(grep -Fxc "sudo </bin/mkdir> <--> <$target>" "$COMMAND_LOG")" -eq 1 ]
			expected_sudo_count=$((expected_sudo_count + 1))
		fi
	done
	[ "$(grep -c '^sudo ' "$COMMAND_LOG")" -eq "$expected_sudo_count" ]
	assert_log_order \
		"nix run .#darwin-rebuild -- switch --flake .#macos --impure" \
		"sudo </usr/sbin/chown> <test-user:admin> </usr/local/bin>" \
		"sudo </bin/chmod> <0775> </usr/local/bin>" \
		"sudo </usr/sbin/chown> <test-user:admin> </usr/local/cli-plugins>" \
		"sudo </bin/chmod> <0775> </usr/local/cli-plugins>" \
		"update-homebrew-casks " \
		"docker info"
}

@test "Linux harness stubs macOS-only parent inspection" {
	write_installed_stubs

	run_macos_installer_for_host Linux

	[ "$status" -eq 0 ]
	grep -Fqx 'sudo </usr/sbin/chown> <test-user:admin> </usr/local/bin>' "$COMMAND_LOG"
	grep -Fqx 'sudo </usr/sbin/chown> <test-user:admin> </usr/local/cli-plugins>' "$COMMAND_LOG"
}

@test "test boundary converges only six exact sudo argv vectors" {
	local command
	reset_test_homebrew_cask_link_targets

	run_test_homebrew_cask_link_convergence

	[ "$status" -eq 0 ]
	for command in \
		"sudo </bin/mkdir> <--> <$TEST_HOMEBREW_CASK_BIN_DIR>" \
		"sudo </usr/sbin/chown> <test-user:admin> <$TEST_HOMEBREW_CASK_BIN_DIR>" \
		"sudo </bin/chmod> <0775> <$TEST_HOMEBREW_CASK_BIN_DIR>" \
		"sudo </bin/mkdir> <--> <$TEST_HOMEBREW_CASK_CLI_PLUGIN_DIR>" \
		"sudo </usr/sbin/chown> <test-user:admin> <$TEST_HOMEBREW_CASK_CLI_PLUGIN_DIR>" \
		"sudo </bin/chmod> <0775> <$TEST_HOMEBREW_CASK_CLI_PLUGIN_DIR>"; do
		[ "$(grep -Fxc "$command" "$COMMAND_LOG")" -eq 1 ]
	done
	[ "$(grep -c '^sudo ' "$COMMAND_LOG")" -eq 6 ]
	assert_log_order \
		"sudo </bin/mkdir> <--> <$TEST_HOMEBREW_CASK_BIN_DIR>" \
		"sudo </usr/sbin/chown> <test-user:admin> <$TEST_HOMEBREW_CASK_BIN_DIR>" \
		"sudo </bin/chmod> <0775> <$TEST_HOMEBREW_CASK_BIN_DIR>" \
		"sudo </bin/mkdir> <--> <$TEST_HOMEBREW_CASK_CLI_PLUGIN_DIR>" \
		"sudo </usr/sbin/chown> <test-user:admin> <$TEST_HOMEBREW_CASK_CLI_PLUGIN_DIR>" \
		"sudo </bin/chmod> <0775> <$TEST_HOMEBREW_CASK_CLI_PLUGIN_DIR>" \
		"update-homebrew-casks "
}

@test "unsafe Homebrew cask link targets stop all privileged mutations" {
	local scenario kind target expected

	for scenario in \
		"symlink:$TEST_HOMEBREW_CASK_BIN_DIR" \
		"file:$TEST_HOMEBREW_CASK_BIN_DIR" \
		"symlink:$TEST_HOMEBREW_CASK_CLI_PLUGIN_DIR" \
		"file:$TEST_HOMEBREW_CASK_CLI_PLUGIN_DIR"; do
		kind="${scenario%%:*}"
		target="${scenario#*:}"
		reset_test_homebrew_cask_link_targets
		case "$kind" in
		symlink)
			ln -s "$TEST_HOMEBREW_LINK_TARGET" "$target"
			expected="Refusing symbolic Homebrew cask link directory: $target"
			;;
		file)
			touch "$target"
			expected="Homebrew cask link path is not a directory: $target"
			;;
		esac

		run_test_homebrew_cask_link_convergence

		[ "$status" -ne 0 ]
		[[ "$output" == *"$expected"* ]]
		assert_no_homebrew_cask_link_mutations
		! grep -q '^update-homebrew-casks ' "$COMMAND_LOG"
	done
}

@test "target replacement after global preflight is revalidated before its mutation" {
	reset_test_homebrew_cask_link_targets
	export SUDO_SWAP_CLI_PLUGIN_TARGET=1

	run_test_homebrew_cask_link_convergence

	[ "$status" -ne 0 ]
	[[ "$output" == *"Refusing symbolic Homebrew cask link directory: $TEST_HOMEBREW_CASK_CLI_PLUGIN_DIR"* ]]
	[ "$(grep -Fc "<$TEST_HOMEBREW_CASK_BIN_DIR>" "$COMMAND_LOG")" -eq 3 ]
	! grep -Fq "<$TEST_HOMEBREW_CASK_CLI_PLUGIN_DIR>" "$COMMAND_LOG"
	! grep -q '^update-homebrew-casks ' "$COMMAND_LOG"
}

@test "privileged mutation failures stop later mutations and cask updates" {
	local operation expected_count
	for operation in mkdir chown chmod; do
		reset_test_homebrew_cask_link_targets
		export SUDO_FAIL_OPERATION="$operation"
		case "$operation" in
		mkdir) expected_count=1 ;;
		chown) expected_count=2 ;;
		chmod) expected_count=3 ;;
		esac

		run_test_homebrew_cask_link_convergence

		[ "$status" -eq "$SUDO_FAILURE_STATUS" ]
		[ "$(grep -c '^sudo ' "$COMMAND_LOG")" -eq "$expected_count" ]
		! grep -Fq "<$TEST_HOMEBREW_CASK_CLI_PLUGIN_DIR>" "$COMMAND_LOG"
		! grep -q '^update-homebrew-casks ' "$COMMAND_LOG"
	done
}

@test "sudo boundary rejects unknown argv without executing it" {
	local unexpected="$BATS_TEST_TMPDIR/unexpected-touch"

	run "$STUB_BIN/sudo" /usr/bin/touch "$unexpected"

	[ "$status" -eq 97 ]
	[[ "$output" == *"Unexpected sudo argv: </usr/bin/touch> <$unexpected>"* ]]
	[ ! -e "$unexpected" ]
}

@test "cask update failure stops macOS before Docker runtime and chezmoi" {
	write_installed_stubs
	export HOMEBREW_CASK_UPDATE_STATUS=47

	run_macos_installer

	[ "$status" -eq 47 ]
	grep -q '^update-homebrew-casks ' "$COMMAND_LOG"
	! grep -q '^chezmoi ' "$COMMAND_LOG"
	! grep -q '^verify-environment ' "$COMMAND_LOG"
}

@test "repairs Homebrew cask link directories before cask updates" {
	write_installed_stubs
	mkdir -p "$FAKE_HOMEBREW_BIN_DIR" "$FAKE_HOMEBREW_CLI_PLUGINS_DIR"
	chmod 0700 "$FAKE_HOMEBREW_BIN_DIR" "$FAKE_HOMEBREW_CLI_PLUGINS_DIR"

	run_macos_installer

	[ "$status" -eq 0 ]
	grep -Fqx "sudo </usr/sbin/chown> <test-user:admin> <$FAKE_HOMEBREW_BIN_DIR>" "$COMMAND_LOG"
	grep -Fqx "sudo </bin/chmod> <0775> <$FAKE_HOMEBREW_BIN_DIR>" "$COMMAND_LOG"
	grep -Fqx "sudo </usr/sbin/chown> <test-user:admin> <$FAKE_HOMEBREW_CLI_PLUGINS_DIR>" "$COMMAND_LOG"
	grep -Fqx "sudo </bin/chmod> <0775> <$FAKE_HOMEBREW_CLI_PLUGINS_DIR>" "$COMMAND_LOG"
	assert_log_order \
		"sudo </usr/sbin/chown> <test-user:admin> <$FAKE_HOMEBREW_BIN_DIR>" \
		"sudo </bin/chmod> <0775> <$FAKE_HOMEBREW_BIN_DIR>" \
		"nix run .#darwin-rebuild -- switch --flake .#macos --impure" \
		"update-homebrew-casks "
}

@test "rejects an unsafe Homebrew cask link directory before privileged changes" {
	write_installed_stubs
	mkdir -p "$FAKE_HOMEBREW_BIN_DIR" "$FAKE_HOMEBREW_CLI_PLUGINS_DIR"
	rmdir "$FAKE_HOMEBREW_CLI_PLUGINS_DIR"
	ln -s "$FAKE_HOMEBREW_BIN_DIR" "$FAKE_HOMEBREW_CLI_PLUGINS_DIR"

	run "$INSTALLER"

	[ "$status" -ne 0 ]
	[[ "$output" == *"Homebrew cask link directory must be a real directory"* ]]
	! grep -Fq 'sudo </usr/sbin/chown>' "$COMMAND_LOG"
	! grep -Fq 'sudo </bin/chmod>' "$COMMAND_LOG"
	! grep -q "^update-homebrew-casks " "$COMMAND_LOG"
}

@test "Hermes bootstrap failure recovers macOS runtime before returning failure" {
	write_installed_stubs
	export HERMES_BOOTSTRAP_STATUS=45

	run_macos_installer

	[ "$status" -eq 45 ]
	grep -q 'hermes-bootstrap apply' "$COMMAND_LOG"
	! grep -q ' up -d --force-recreate' "$COMMAND_LOG"
	grep -q ' start' "$COMMAND_LOG"
	! grep -q ' up ' "$COMMAND_LOG"
	! grep -q '^verify-environment ' "$COMMAND_LOG"
}

@test "existing shell rc files are preserved before nix-darwin activation" {
	write_installed_stubs
	mkdir -p "$(dirname "$FAKE_BASHRC")"
	printf 'existing bashrc\n' >"$FAKE_BASHRC"
	printf 'existing zshrc\n' >"$FAKE_ZSHRC"

	run_macos_installer

	[ "$status" -eq 0 ]
	[ ! -e "$FAKE_BASHRC" ]
	[ ! -e "$FAKE_ZSHRC" ]
	grep -q '^existing bashrc$' "$FAKE_BASHRC.before-nix-darwin"
	grep -q '^existing zshrc$' "$FAKE_ZSHRC.before-nix-darwin"
	assert_log_order \
		"sudo <mv> <$FAKE_BASHRC> <$FAKE_BASHRC.before-nix-darwin>" \
		"sudo <mv> <$FAKE_ZSHRC> <$FAKE_ZSHRC.before-nix-darwin>" \
		"nix run .#darwin-rebuild -- switch --flake .#macos --impure"
}

@test "running Docker Desktop is stopped when its engine is unavailable" {
	write_installed_stubs
	cat >"$FAKE_DOCKER_APP/Contents/Resources/bin/docker" <<'EOF'
#!/usr/bin/env bash
printf 'docker %s\n' "$*" >>"$COMMAND_LOG"
if [ "${1:-}" = "info" ] && ! grep -q 'nix run .#darwin-rebuild' "$COMMAND_LOG"; then
	exit 1
fi
case " $* " in
  *" hermes-bootstrap secret-plan "*) printf '%s\n' "$HERMES_SECRET_PLAN" ;;
  *" hermes-bootstrap apply "*) cat >"$PAYLOAD_CAPTURE"; exit "$HERMES_BOOTSTRAP_STATUS" ;;
esac
EOF
	chmod +x "$FAKE_DOCKER_APP/Contents/Resources/bin/docker"

	run_macos_installer

	[ "$status" -eq 0 ]
	assert_log_order \
		"pgrep -x com.docker.backend" \
		"docker desktop stop --timeout 120" \
		"nix run .#darwin-rebuild -- switch --flake .#macos --impure"
}

@test "nix-darwin user profile provides chezmoi after activation" {
	write_installed_stubs
	rm "$STUB_BIN/chezmoi"
	mkdir -p "$FAKE_USER_PROFILE_ROOT/test-user/bin"
	cat >"$FAKE_USER_PROFILE_ROOT/test-user/bin/chezmoi" <<'EOF'
#!/usr/bin/env bash
printf 'profile-chezmoi %s\n' "$*" >>"$COMMAND_LOG"
EOF
	chmod +x "$FAKE_USER_PROFILE_ROOT/test-user/bin/chezmoi"

	run_macos_installer

	[ "$status" -eq 0 ]
	grep -q "^profile-chezmoi init --source $REPO_ROOT/chezmoi$" "$COMMAND_LOG"
	grep -q '^profile-chezmoi apply --force$' "$COMMAND_LOG"
}

@test "nix-darwin switch failure stops before runtime setup" {
	write_installed_stubs
	write_stub nix '
printf "nix %s\n" "$*" >>"$COMMAND_LOG"
if [ "${1:-}" = "run" ]; then exit 42; fi
'

	run_macos_installer

	[ "$status" -eq 42 ]
	! grep -q '^chezmoi ' "$COMMAND_LOG"
	! grep -q '^docker compose ' "$COMMAND_LOG"
}

@test "fresh install provisions Nix then delegates apps and Rosetta to nix-darwin" {
	write_fresh_install_stubs
	rmdir "$FAKE_HOMEBREW_BIN_DIR" "$FAKE_HOMEBREW_CLI_PLUGINS_DIR"

	run_macos_installer

	[ "$status" -eq 0 ]
	grep -Fqx "sudo </bin/mkdir> <--> <$FAKE_HOMEBREW_BIN_DIR>" "$COMMAND_LOG"
	grep -Fqx "sudo </bin/mkdir> <--> <$FAKE_HOMEBREW_CLI_PLUGINS_DIR>" "$COMMAND_LOG"
	assert_log_order \
		"nix-installer --daemon" \
		"nix run .#darwin-rebuild -- switch --flake .#macos --impure" \
		"docker-install --accept-license --user=test-user" \
		"chezmoi init --source $REPO_ROOT/chezmoi"
	[ "$(grep -c 'nix-installer --daemon' "$COMMAND_LOG")" -eq 1 ]
	! grep -q 'raw.githubusercontent.com/Homebrew/install' "$COMMAND_LOG"
	! grep -q 'brew install --cask' "$COMMAND_LOG"
	! grep -q 'desktop.docker.com/mac' "$COMMAND_LOG"
	! grep -q 'softwareupdate' "$COMMAND_LOG"
}

@test "macOS installer contains no imperative application installer fallback" {
	grep -q 'run .#darwin-rebuild -- switch --flake .#macos --impure' "$INSTALLER"
	! grep -q 'brew install --cask' "$INSTALLER"
	! grep -q 'desktop.docker.com/mac' "$INSTALLER"
}

@test "a checkout already at the dotfiles target is kept in place" {
	write_installed_stubs
	rm "$HOME/.dotfiles"
	mkdir -p \
		"$HOME/.dotfiles/scripts/sh" \
		"$HOME/.dotfiles/chezmoi" \
		"$HOME/.dotfiles/docker/hermes-agent"
	cp "$INSTALLER" "$HOME/.dotfiles/scripts/sh/install-macos.sh"
	cp "$COMMON_INSTALLER" "$HOME/.dotfiles/scripts/sh/install-common.sh"
	cp "$HERMES_INSTALLER" "$HOME/.dotfiles/scripts/sh/hermes-agent.sh"
	cp "$REPO_ROOT/scripts/sh/hermes-hindsight.sh" "$HOME/.dotfiles/scripts/sh/hermes-hindsight.sh"
	cp "$REPO_ROOT/docker/hermes-agent/hindsight.env" "$HOME/.dotfiles/docker/hermes-agent/hindsight.env"
	touch \
		"$HOME/.dotfiles/flake.nix" \
		"$HOME/.dotfiles/docker/hermes-agent/compose.yml"
	INSTALLER="$HOME/.dotfiles/scripts/sh/install-macos.sh"

	run_macos_installer

	[ "$status" -eq 0 ]
	[ -d "$HOME/.dotfiles" ]
	[ ! -L "$HOME/.dotfiles" ]
	[ -f "$HOME/.dotfiles/scripts/sh/install-macos.sh" ]
	[ "$(find "$HOME" -maxdepth 1 -name '.dotfiles.backup.*' | wc -l | tr -d ' ')" -eq 0 ]
}

@test "an existing dotfiles directory is moved to a timestamped backup" {
	write_installed_stubs
	rm "$HOME/.dotfiles"
	mkdir -p "$HOME/.dotfiles"
	echo keep >"$HOME/.dotfiles/existing.txt"

	run_macos_installer

	[ "$status" -eq 0 ]
	[ -L "$HOME/.dotfiles" ]
	[ -f "$HOME/.dotfiles.backup.20260717010203/existing.txt" ]
	[ "$(find "$HOME" -maxdepth 1 -name '.dotfiles.backup.*' | wc -l | tr -d ' ')" -eq 1 ]
}

@test "Docker engine readiness timeout fails after the configured attempt count" {
	write_installed_stubs
	cat >"$FAKE_DOCKER_APP/Contents/Resources/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf "docker %s\n" "$*" >>"$COMMAND_LOG"
if [ "${1:-}" = "info" ]; then exit 1; fi
exit 0
EOF
	chmod +x "$FAKE_DOCKER_APP/Contents/Resources/bin/docker"

	run_macos_installer

	[ "$status" -ne 0 ]
	[[ "$output" == *"Timed out waiting for Docker Desktop engine after 2 attempts."* ]]
	[ "$(grep -c '^docker info$' "$COMMAND_LOG")" -eq 3 ]
}
