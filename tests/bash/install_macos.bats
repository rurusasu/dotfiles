#!/usr/bin/env bats

setup() {
	# Do not let the caller's Git command-config environment change the
	# incomplete-config fixtures below. Each test declares the variables it needs.
	for git_config_variable in $(env | sed -n 's/^\(GIT_CONFIG_COUNT\|GIT_CONFIG_KEY_[0-9][0-9]*\|GIT_CONFIG_VALUE_[0-9][0-9]*\)=.*/\1/p'); do
		unset "$git_config_variable"
	done
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	INSTALLER="$REPO_ROOT/scripts/sh/install-macos.sh"
	COMMON_INSTALLER="$REPO_ROOT/scripts/sh/install-common.sh"
	TEST_HOME="$BATS_TEST_TMPDIR/home"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"
	FAKE_DOCKER_APP="$BATS_TEST_TMPDIR/Applications/Docker.app"
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
	FAKE_DOCKER_CASK_STATE="$BATS_TEST_TMPDIR/docker-cask-installed"
	REAL_JQ="$(command -v jq)"
	REAL_TIMEOUT="$(command -v timeout)"
	REAL_TASK="$(command -v task)"
	REAL_PYTHON="$(command -v python3)"
	REAL_BASH="$(command -v bash)"
	mkdir -p "$TEST_HOME" "$STUB_BIN" "$TEST_HOMEBREW_CASK_PARENT_DIR" "$TEST_HOMEBREW_LINK_TARGET"
	chmod 0755 "$TEST_HOMEBREW_CASK_PARENT_DIR"
	: >"$COMMAND_LOG"
	: >"$FAKE_NIX_PROFILE"

	export HOME="$TEST_HOME"
	export USER="test-user"
	export SUDO_USER="test-user"
	unset DOTFILES_USER
	export PATH="$STUB_BIN:/usr/bin:/bin"
	export COMMAND_LOG STUB_BIN REAL_JQ REAL_TIMEOUT INSTALLER REPO_ROOT
	export REAL_TASK REAL_PYTHON REAL_BASH
	export MACOS_TEST_BOUNDARY="$REPO_ROOT/tests/bash/helpers/macos_install_boundary.sh"
	export FAKE_BASHRC FAKE_ZSHRC FAKE_DOCKER_APP
	export FAKE_HOMEBREW_BIN_DIR FAKE_HOMEBREW_CLI_PLUGINS_DIR
	export FAKE_DOCKER_CASK_STATE
	export TEST_HOMEBREW_CASK_PARENT_DIR TEST_HOMEBREW_CASK_BIN_DIR
	export TEST_HOMEBREW_CASK_CLI_PLUGIN_DIR TEST_HOMEBREW_LINK_TARGET
	export DOTFILES_DOCKER_APP_PATH="$FAKE_DOCKER_APP"
	export DOTFILES_LAUNCHCTL_COMMAND="$STUB_BIN/launchctl"
	export DOTFILES_OPEN_COMMAND="$STUB_BIN/open"
	export DOTFILES_ACCEPT_DOCKER_LICENSE=1
	export DOTFILES_DOCKER_SETUP_MARKER="$TEST_HOME/.config/dotfiles/docker-desktop-installed"
	export DOTFILES_NIX_PROFILE_SCRIPT="$FAKE_NIX_PROFILE"
	export DOTFILES_BASHRC_PATH="$FAKE_BASHRC"
	export DOTFILES_ZSHRC_PATH="$FAKE_ZSHRC"
	export DOTFILES_USER_PROFILE_ROOT="$FAKE_USER_PROFILE_ROOT"
	export DOTFILES_HOMEBREW_BIN_DIR="$FAKE_HOMEBREW_BIN_DIR"
	export DOTFILES_HOMEBREW_CLI_PLUGINS_DIR="$FAKE_HOMEBREW_CLI_PLUGINS_DIR"
	export DOTFILES_DOCKER_WAIT_ATTEMPTS=2
	export DOTFILES_DOCKER_PROBE_TIMEOUT_SECONDS=1
	export DOTFILES_WAIT_SLEEP_SECONDS=0
	export DOTFILES_VERIFY_ENVIRONMENT="$STUB_BIN/verify-environment"
	export DOTFILES_HERMES_CURL_EXECUTABLE="$STUB_BIN/curl"
	export DOTFILES_HOMEBREW_CASK_BIN_DIR="$BATS_TEST_TMPDIR/untrusted/bin"
	export DOTFILES_HOMEBREW_CASK_CLI_PLUGIN_DIR="$BATS_TEST_TMPDIR/untrusted/cli-plugins"
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
exit 0
'
	write_stub open 'printf "open %s\n" "$*" >>"$COMMAND_LOG"'
	write_stub npm '
prefix="${NPM_CONFIG_PREFIX:-$HOME/.local/npm}"
mkdir -p "$prefix/bin"
printf "npm %s prefix=%s\n" "$*" "$prefix" >>"$COMMAND_LOG"
printf "#!/usr/bin/env bash\nexit 0\n" >"$prefix/bin/codex"
chmod +x "$prefix/bin/codex"
'
	# Activation prepends host/profile paths. Keep this offline boundary explicit
	# and never let an inherited prefix redirect fixture writes outside TEST_HOME.
	export DOTFILES_NPM_COMMAND="$STUB_BIN/npm"
	export CODEX_NPM_PREFIX="$TEST_HOME/.local/npm"
	write_stub brew '
if [[ ${1:-} == list && ${2:-} == --cask && ${3:-} == --versions &&
	${4:-} == docker-desktop && -f $FAKE_DOCKER_CASK_STATE ]]; then
	printf "docker-desktop 4.89.0\n"
	exit 0
fi
exit 1
'
	export DOTFILES_BREW_COMMAND="$STUB_BIN/brew"
	write_stub pgrep '
printf "pgrep %s\n" "$*" >>"$COMMAND_LOG"
exit 0
'
	write_stub sleep 'exit 0'
	write_stub date 'echo 20260717010203'
	write_stub install-fake-docker-cask-artifacts '
mkdir -p "$FAKE_HOMEBREW_BIN_DIR" "$FAKE_HOMEBREW_CLI_PLUGINS_DIR"
for mapping in \
	"$FAKE_HOMEBREW_BIN_DIR/docker:$FAKE_DOCKER_APP/Contents/Resources/bin/docker" \
	"$FAKE_HOMEBREW_BIN_DIR/docker-credential-desktop:$FAKE_DOCKER_APP/Contents/Resources/bin/docker-credential-desktop" \
	"$FAKE_HOMEBREW_BIN_DIR/docker-credential-ecr-login:$FAKE_DOCKER_APP/Contents/Resources/bin/docker-credential-ecr-login" \
	"$FAKE_HOMEBREW_BIN_DIR/docker-credential-osxkeychain:$FAKE_DOCKER_APP/Contents/Resources/bin/docker-credential-osxkeychain" \
	"$FAKE_HOMEBREW_BIN_DIR/kubectl.docker:$FAKE_DOCKER_APP/Contents/Resources/bin/kubectl" \
	"$FAKE_HOMEBREW_CLI_PLUGINS_DIR/docker-compose:$FAKE_DOCKER_APP/Contents/Resources/cli-plugins/docker-compose"; do
	link_path="${mapping%%:*}"
	link_target="${mapping#*:}"
	rm -f -- "$link_path"
	ln -s "$link_target" "$link_path"
done
if [[ ! -e $FAKE_HOMEBREW_BIN_DIR/kubectl && ! -L $FAKE_HOMEBREW_BIN_DIR/kubectl ]]; then
	ln -s "$FAKE_DOCKER_APP/Contents/Resources/bin/kubectl" "$FAKE_HOMEBREW_BIN_DIR/kubectl"
fi
touch "$FAKE_DOCKER_CASK_STATE"
'
	export FAKE_DOCKER_CASK_ARTIFACT_INSTALLER="$STUB_BIN/install-fake-docker-cask-artifacts"
	write_stub sudo '
printf "sudo" >>"$COMMAND_LOG"
printf " <%s>" "$@" >>"$COMMAND_LOG"
printf "\n" >>"$COMMAND_LOG"
is_allowed_cask_target() {
	[[ $1 == /usr/local/bin || $1 == /usr/local/cli-plugins ||
		$1 == "$TEST_HOMEBREW_CASK_BIN_DIR" || $1 == "$TEST_HOMEBREW_CASK_CLI_PLUGIN_DIR" ]]
}
is_allowed_docker_cask_link() {
	case "$1" in
	"$FAKE_HOMEBREW_BIN_DIR/docker" | \
		"$FAKE_HOMEBREW_BIN_DIR/docker-compose" | \
		"$FAKE_HOMEBREW_BIN_DIR/docker-credential-desktop" | \
		"$FAKE_HOMEBREW_BIN_DIR/docker-credential-ecr-login" | \
		"$FAKE_HOMEBREW_BIN_DIR/docker-credential-osxkeychain" | \
		"$FAKE_HOMEBREW_BIN_DIR/kubectl" | \
		"$FAKE_HOMEBREW_BIN_DIR/kubectl.docker" | \
		"$FAKE_HOMEBREW_CLI_PLUGINS_DIR/docker-compose") return 0 ;;
	*) return 1 ;;
	esac
}
fixture_user="${SUDO_USER:-$USER}"
expected_nix_config="NIX_CONFIG=extra-experimental-features = nix-command flakes
accept-flake-config = true"
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
		if [[ $# -eq 12 && ${2:-} == "SUDO_USER=$fixture_user" &&
			${3:-} == "$expected_nix_config" &&
			${4:-} == "$STUB_BIN/nix" && ${5:-} == --accept-flake-config &&
			${6:-} == run && ${7:-} == ".#darwin-rebuild" && ${8:-} == -- &&
			${9:-} == switch && ${10:-} == --flake && ${11:-} == ".#macos" &&
			${12:-} == --impure ]]; then
			exec "$@"
		fi
		;;
	mv|/bin/mv)
		if [[ $# -eq 5 && ${2:-} == -n && ${3:-} == -- ]]; then
			if is_allowed_docker_cask_link "${4:-}" &&
				[[ ${5:-} == "${4:-}.dotfiles-cask-migration-backup" ]]; then
				exec "$@"
			fi
			if [[ ${4:-} == *.dotfiles-cask-migration-backup ]]; then
				original_path="${4%.dotfiles-cask-migration-backup}"
				if is_allowed_docker_cask_link "$original_path" && [[ ${5:-} == "$original_path" ]]; then
					exec "$@"
				fi
			fi
		fi
		if [[ $# -eq 3 &&
			( ${2:-} == "$FAKE_BASHRC" || ${2:-} == "$FAKE_ZSHRC" ) &&
			${3:-} == "${2:-}.before-nix-darwin" ]]; then
			exec "$@"
		fi
		;;
	/bin/rm)
		if [[ $# -eq 4 && ${2:-} == -f && ${3:-} == -- ]]; then
			rm -- "${4:-}"
			exit 0
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
	write_stub verify-environment 'printf "verify-environment compose=%s args=%s\n" "${DOTFILES_COMPOSE_FILE:-}" "$*" >>"$COMMAND_LOG"'
	write_stub jq 'exec "$REAL_JQ" "$@"'
	write_stub task '
printf "task %s\n" "$*" >>"$COMMAND_LOG"
case " $* " in
  *" darwin:install "*) exec "$REAL_TASK" "$@" ;;
  *" hermes:desktop:install "*) exit "${HERMES_DESKTOP_INSTALL_STATUS:-0}" ;;
esac
'
	export DOTFILES_TASK_COMMAND="$STUB_BIN/task"
	write_stub bash '
if [[ ${1:-} == -c && ${2:-} == "source scripts/sh/install-macos.sh; finish_macos_install" ]]; then
  exec "$REAL_BASH" -c '\''source scripts/sh/install-macos.sh; source "$MACOS_TEST_BOUNDARY"; finish_macos_install'\''
fi
exec "$REAL_BASH" "$@"
'
	write_stub python3 '
if [[ ${1:-} == scripts/python/update_darwin_packages.py ]]; then
  printf "python3 %s\n" "$*" >>"$COMMAND_LOG"
  exit "${DARWIN_UPDATE_STATUS:-0}"
fi
exec "$REAL_PYTHON" "$@"
'
}

write_stub() {
	local name="$1"
	local body="$2"
	if [[ $name == nix ]]; then
		body='
if [[ ${1:-} == --accept-flake-config ]]; then
	printf "nix accepted-flake-config\n" >>"$COMMAND_LOG"
	shift
fi
if [[ ${1:-} == --extra-experimental-features ]]; then
  printf "nix %s\n" "$*" >>"$COMMAND_LOG"
  while [[ ${1:-} != --command ]]; do shift; done
  shift
  exec "$@"
fi
'"$body"
	fi
	cat >"$STUB_BIN/$name" <<EOF
#!$REAL_BASH
set -euo pipefail
$body
EOF
	chmod +x "$STUB_BIN/$name"
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

	write_stub nix '
printf "nix %s\n" "$*" >>"$COMMAND_LOG"
if [[ ${1:-} == run ]]; then
	"$FAKE_DOCKER_CASK_ARTIFACT_INSTALLER"
fi
'
	write_stub chezmoi 'printf "chezmoi %s\n" "$*" >>"$COMMAND_LOG"'
	write_stub launchctl 'printf "launchctl %s\n" "$*" >>"$COMMAND_LOG"'
	write_stub docker '
printf "docker %s\n" "$*" >>"$COMMAND_LOG"
case " $* " in
  *" info "*) [[ ${DOCKER_ENGINE_RUNNING:-0} == 1 ]] || exit 1 ;;
esac
'
	ln -s "$REPO_ROOT" "$HOME/.dotfiles"
}

write_fresh_install_stubs() {
	mkdir -p "$FAKE_HOMEBREW_BIN_DIR" "$FAKE_HOMEBREW_CLI_PLUGINS_DIR"
	write_stub curl '
printf "curl %s\n" "$*" >>"$COMMAND_LOG"
case "$*" in
	*/health*) exit 0 ;;
	*install.lix.systems/lix*)
		cat <<'"'"'SCRIPT'"'"'
printf "nix-installer %s\n" "$*" >>"$COMMAND_LOG"
cat >"$STUB_BIN/nix" <<'"'"'NIX'"'"'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == --accept-flake-config ]]; then
  shift
fi
printf "nix %s\n" "$*" >>"$COMMAND_LOG"
if [[ ${1:-} == --extra-experimental-features ]]; then
  while [[ ${1:-} != --command ]]; do shift; done
  shift
  exec "$@"
fi
if [ "${1:-}" = "run" ]; then
	mkdir -p "$DOTFILES_DOCKER_APP_PATH/Contents/MacOS" "$DOTFILES_DOCKER_APP_PATH/Contents/Resources/bin"
		cat >"$DOTFILES_DOCKER_APP_PATH/Contents/MacOS/install" <<'"'"'DOCKER_INSTALL'"'"'
#!/usr/bin/env bash
printf "docker-install %s\n" "$*" >>"$COMMAND_LOG"
DOCKER_INSTALL
		cat >"$DOTFILES_DOCKER_APP_PATH/Contents/Resources/bin/docker" <<'"'"'DOCKER'"'"'
#!/usr/bin/env bash
printf "docker %s\n" "$*" >>"$COMMAND_LOG"
DOCKER
	cat >"$STUB_BIN/chezmoi" <<'"'"'CHEZMOI'"'"'
#!/usr/bin/env bash
printf "chezmoi %s\n" "$*" >>"$COMMAND_LOG"
CHEZMOI
	cat >"$STUB_BIN/launchctl" <<'LAUNCHCTL'
#!/usr/bin/env bash
printf "launchctl %s\n" "$*" >>"$COMMAND_LOG"
LAUNCHCTL
		chmod +x \
			"$DOTFILES_DOCKER_APP_PATH/Contents/MacOS/install" \
			"$DOTFILES_DOCKER_APP_PATH/Contents/Resources/bin/docker" \
			"$STUB_BIN/chezmoi" \
			"$STUB_BIN/launchctl"
	"$FAKE_DOCKER_CASK_ARTIFACT_INSTALLER"
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
  export SUDO_USER=test-user
ensure_homebrew_cask_link_directories_under_parent \
  "$TEST_HOMEBREW_CASK_PARENT_DIR" \
  "$TEST_HOMEBREW_CASK_BIN_DIR" \
  "$TEST_HOMEBREW_CASK_CLI_PLUGIN_DIR"
'
}

run_macos_installer_for_host() {
	shift

	run bash -c '
set -euo pipefail
. "$INSTALLER"
. "$MACOS_TEST_BOUNDARY"
main "$@"
' bash "$@"
}

run_macos_installer() {
	run_macos_installer_for_host "$(/usr/bin/uname -s)" "$@"
}

@test "offline npm fixture survives the real installer PATH prepend" {
	write_installed_stubs
	export NPM_SENTINEL_MARKER="$BATS_TEST_TMPDIR/unexpected-npm-ran"
	local prepended_bin="$FAKE_DOCKER_APP/Contents/Resources/bin"
	mkdir -p "$prepended_bin"
	write_stub unexpected-npm '
printf "unexpected npm\n" >"$NPM_SENTINEL_MARKER"
exit 47
'
	mv "$STUB_BIN/unexpected-npm" "$prepended_bin/npm"

	# Removing only the explicit seam must select the harmless fixture sentinel,
	# not npm from the host. Exercise the production PATH refresh itself.
	run env -u DOTFILES_NPM_COMMAND bash -c '
set -euo pipefail
. "$INSTALLER"
. "$MACOS_TEST_BOUNDARY"
export DOTFILES_ROOT="$REPO_ROOT"
apply_darwin_system
[[ $(command -v npm) == "$FAKE_DOCKER_APP/Contents/Resources/bin/npm" ]]
dotfiles_install_codex_npm
'
	[ "$status" -eq 47 ]
	[ -f "$NPM_SENTINEL_MARKER" ]
	rm "$NPM_SENTINEL_MARKER"
	: >"$COMMAND_LOG"

	run_macos_installer

	[ "$status" -eq 0 ]
	[ ! -e "$NPM_SENTINEL_MARKER" ]
	grep -Fqx "npm install --global --no-audit --no-fund @openai/codex@latest prefix=$TEST_HOME/.local/npm" "$COMMAND_LOG"
	[ -x "$TEST_HOME/.local/npm/bin/codex" ]
	[ "${CODEX_NPM_PREFIX:-}" = "$TEST_HOME/.local/npm" ]
}

@test "extended ACL grant on Homebrew cask link parent stops before privileged mutation" {
	export TEST_HOMEBREW_PARENT_ACL_STATE=present

	run_test_homebrew_cask_link_convergence

	[ "$status" -ne 0 ]
	[[ "$output" == *"Homebrew cask link parent must not have an extended ACL: $TEST_HOMEBREW_CASK_PARENT_DIR"* ]]
	assert_no_homebrew_cask_link_mutations
}

@test "caller-writable Homebrew cask link parent stops before privileged mutation" {
	export TEST_HOMEBREW_PARENT_IMMUTABLE_TO_CALLER=0

	run_test_homebrew_cask_link_convergence

	[ "$status" -ne 0 ]
	[[ "$output" == *"Homebrew cask link parent must not be writable by the current caller: $TEST_HOMEBREW_CASK_PARENT_DIR"* ]]
	assert_no_homebrew_cask_link_mutations
}

@test "default installation applies core configuration and managed runtimes" {
	write_installed_stubs

	run_macos_installer

	[ "$status" -eq 0 ]
	[ "$(grep -Fc 'nix accepted-flake-config' "$COMMAND_LOG")" -eq 2 ]
	assert_log_order \
		"nix flake update --flake $REPO_ROOT" \
		"python3 scripts/python/update_darwin_packages.py --write --output darwin-package-update.json" \
		"nix run .#darwin-rebuild -- switch --flake .#macos --impure" \
		"verify-environment compose= args="
	! grep -q '^brew uninstall' "$COMMAND_LOG"
}

@test "package update failure prevents macOS activation" {
	write_installed_stubs
	export DARWIN_UPDATE_STATUS=42
	run_macos_installer
	[ "$status" -eq 42 ]
	[[ "$output" == *"[FAILED] Checking custom macOS package updates (exit 42)"* ]]
	grep -q 'python3 scripts/python/update_darwin_packages.py' "$COMMAND_LOG"
	! grep -q 'nix run .#darwin-rebuild' "$COMMAND_LOG"
}

@test "flake download failure names the phase and stops the workflow" {
	write_installed_stubs
	write_stub nix '
printf "nix %s\n" "$*" >>"$COMMAND_LOG"
printf "error: Truncated tar archive\n" >&2
exit 37
'
	run_macos_installer
	[ "$status" -eq 37 ]
	[[ "$output" == *"Large source downloads can take time"* ]]
	[[ "$output" == *"Truncated tar archive"* ]]
	[[ "$output" == *"[FAILED] Updating flake inputs (exit 37)"* ]]
	[[ "$output" != *"[DONE] Updating flake inputs"* ]]
	! grep -q 'nix shell\|darwin-rebuild' "$COMMAND_LOG"
}

@test "pinned installer mode skips both flake and custom package updates" {
	write_installed_stubs
	export DOTFILES_SKIP_FLAKE_UPDATE=1
	run_macos_installer
	[ "$status" -eq 0 ]
	[[ "$output" == *"[SKIPPED] Updating flake inputs"* ]]
	[[ "$output" != *"[DONE] Updating flake inputs"* ]]
	! grep -q 'nix flake update\|darwin:update' "$COMMAND_LOG"
	grep -q 'nix run .#darwin-rebuild' "$COMMAND_LOG"
}

@test "macOS installer clears an incomplete inherited Git command config" {
	write_installed_stubs
	write_stub nix '
	env | grep -Eq "^GIT_CONFIG_(COUNT|KEY_[0-9]+|VALUE_[0-9]+)=" && exit 43
printf "nix %s\n" "$*" >>"$COMMAND_LOG"
if [[ ${1:-} == run ]]; then "$FAKE_DOCKER_CASK_ARTIFACT_INSTALLER"; fi
'
	export GIT_CONFIG_COUNT=2
	unset GIT_CONFIG_KEY_0 GIT_CONFIG_KEY_1
	export GIT_CONFIG_VALUE_0=one
	export GIT_CONFIG_VALUE_1=two

	run_macos_installer

	[ "$status" -eq 0 ]
}

@test "macOS installer clears an inherited Git command config with an empty key" {
	write_installed_stubs
	write_stub nix '
env | grep -Eq "^GIT_CONFIG_(COUNT|KEY_[0-9]+|VALUE_[0-9]+)=" && exit 43
printf "nix %s\n" "$*" >>"$COMMAND_LOG"
if [[ ${1:-} == run ]]; then "$FAKE_DOCKER_CASK_ARTIFACT_INSTALLER"; fi
'
	export GIT_CONFIG_COUNT=1
	export GIT_CONFIG_KEY_0=''
	export GIT_CONFIG_VALUE_0=one

	run_macos_installer

	[ "$status" -eq 0 ]
}

@test "installation activates the native Nix gateway and Docker" {
	write_installed_stubs

	run_macos_installer

	[ "$status" -eq 0 ]
	assert_log_order \
		"nix flake update --flake $REPO_ROOT" \
		"nix run .#darwin-rebuild -- switch --flake .#macos --impure" \
		"task --dir $REPO_ROOT hermes:desktop:install" \
		"verify-environment compose= args="
	! grep -q '^task .*hermes:docker:' "$COMMAND_LOG"
	! grep -q '^op ' "$COMMAND_LOG"
	! grep -q 'brew install --cask' "$COMMAND_LOG"
	! grep -q 'desktop.docker.com/mac' "$COMMAND_LOG"
	! grep -q 'docker-install' "$COMMAND_LOG"
}

@test "native Nix activation preserves unrelated Docker services" {
	write_installed_stubs
	export DOCKER_ENGINE_RUNNING=1

	run_macos_installer

	[ "$status" -eq 0 ]
	activation_line="$(grep -nF 'nix run .#darwin-rebuild -- switch --flake .#macos --impure' "$COMMAND_LOG" | cut -d: -f1)"
	[ -n "$activation_line" ]
	! grep -q 'docker compose .* hermes' "$COMMAND_LOG"
}

@test "help documents the standard installation" {
	run "$INSTALLER" --help

	[ "$status" -eq 0 ]
}

@test "unknown install profile stops before mutation" {
	write_installed_stubs

	run_macos_installer --with-unknown

	[ "$status" -ne 0 ]
	[[ "$output" == *"Unknown argument: --with-unknown"* ]]
	[ ! -s "$COMMAND_LOG" ]
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

	export USER=root
	export SUDO_USER="$runner_user"
	export DOTFILES_USER="obsolete-override"
	run_macos_installer

	[ "$status" -eq 0 ]
	! grep -Fq '<DOTFILES_USER=' "$COMMAND_LOG"
	grep -Fq "sudo </usr/bin/env> <SUDO_USER=$runner_user> <NIX_CONFIG=extra-experimental-features = nix-command flakes" "$COMMAND_LOG"
	grep -Fqx "sudo </usr/sbin/chown> <$runner_user:admin> </usr/local/bin>" "$COMMAND_LOG"
	grep -Fqx "sudo </usr/sbin/chown> <$runner_user:admin> </usr/local/cli-plugins>" "$COMMAND_LOG"
}

@test "production Homebrew cask link directories are fixed before cask updates" {
	write_installed_stubs
	local expected_sudo_count=9 target

	run_macos_installer

	[ "$status" -eq 0 ]
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
		"sudo </bin/chmod> <0775> </usr/local/cli-plugins>"
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
		"sudo </bin/chmod> <0775> <$TEST_HOMEBREW_CASK_CLI_PLUGIN_DIR>"
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
}

@test "privileged mutation failures stop later installer stages" {
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
	done
}

@test "sudo boundary rejects unknown argv without executing it" {
	local unexpected="$BATS_TEST_TMPDIR/unexpected-touch"

	run "$STUB_BIN/sudo" /usr/bin/touch "$unexpected"

	[ "$status" -eq 97 ]
	[[ "$output" == *"Unexpected sudo argv: </usr/bin/touch> <$unexpected>"* ]]
	[ ! -e "$unexpected" ]
}

@test "repairs Homebrew cask link directories before later installer stages" {
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
		"nix run .#darwin-rebuild -- switch --flake .#macos --impure"
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
}

@test "native Hermes Desktop install failure stops later verification" {
	write_installed_stubs
	export HERMES_DESKTOP_INSTALL_STATUS=45

	run_macos_installer

	[ "$status" -eq 45 ]
	grep -Fq "task --dir $REPO_ROOT hermes:desktop:install" "$COMMAND_LOG"
	! grep -q 'hermes-bootstrap apply' "$COMMAND_LOG"
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

@test "existing shell rc backups are refreshed before nix-darwin activation" {
	write_installed_stubs
	mkdir -p "$(dirname "$FAKE_BASHRC")"
	printf 'current bashrc\n' >"$FAKE_BASHRC"
	printf 'current zshrc\n' >"$FAKE_ZSHRC"
	printf 'stale bashrc backup\n' >"$FAKE_BASHRC.before-nix-darwin"
	printf 'stale zshrc backup\n' >"$FAKE_ZSHRC.before-nix-darwin"

	run_macos_installer

	[ "$status" -eq 0 ]
	grep -q '^current bashrc$' "$FAKE_BASHRC.before-nix-darwin"
	grep -q '^current zshrc$' "$FAKE_ZSHRC.before-nix-darwin"
	! grep -q '^stale ' "$FAKE_BASHRC.before-nix-darwin"
	! grep -q '^stale ' "$FAKE_ZSHRC.before-nix-darwin"
	assert_log_order \
		"sudo </bin/rm> <-f> <--> <$FAKE_BASHRC.before-nix-darwin>" \
		"sudo </bin/rm> <-f> <--> <$FAKE_ZSHRC.before-nix-darwin>" \
		"sudo <mv> <$FAKE_BASHRC> <$FAKE_BASHRC.before-nix-darwin>" \
		"sudo <mv> <$FAKE_ZSHRC> <$FAKE_ZSHRC.before-nix-darwin>"
}

@test "orphaned shell rc backups are removed before nix-darwin activation" {
	write_installed_stubs
	mkdir -p "$(dirname "$FAKE_BASHRC")"
	printf 'orphaned bashrc backup\n' >"$FAKE_BASHRC.before-nix-darwin"
	printf 'orphaned zshrc backup\n' >"$FAKE_ZSHRC.before-nix-darwin"

	run_macos_installer

	[ "$status" -eq 0 ]
	[ ! -e "$FAKE_BASHRC.before-nix-darwin" ]
	[ ! -e "$FAKE_ZSHRC.before-nix-darwin" ]
	assert_log_order \
		"sudo </bin/rm> <-f> <--> <$FAKE_BASHRC.before-nix-darwin>" \
		"sudo </bin/rm> <-f> <--> <$FAKE_ZSHRC.before-nix-darwin>" \
		"nix run .#darwin-rebuild -- switch --flake .#macos --impure"
}

@test "directory shell rc backups are preserved and stop nix-darwin activation" {
	write_installed_stubs
	mkdir -p "$(dirname "$FAKE_BASHRC")"
	printf 'current bashrc\n' >"$FAKE_BASHRC"
	mkdir "$FAKE_BASHRC.before-nix-darwin"
	printf 'keep this file\n' >"$FAKE_BASHRC.before-nix-darwin/keep"

	run_macos_installer

	[ "$status" -ne 0 ]
	[ -d "$FAKE_BASHRC.before-nix-darwin" ]
	grep -q '^keep this file$' "$FAKE_BASHRC.before-nix-darwin/keep"
	grep -q '^current bashrc$' "$FAKE_BASHRC"
	! grep -q '^sudo <mv>' "$COMMAND_LOG"
	! grep -q '^nix run .#darwin-rebuild -- switch' "$COMMAND_LOG"
}

@test "all shell rc backups are validated before any backup is removed" {
	write_installed_stubs
	mkdir -p "$(dirname "$FAKE_BASHRC")"
	printf 'current bashrc\n' >"$FAKE_BASHRC"
	printf 'stale bashrc backup\n' >"$FAKE_BASHRC.before-nix-darwin"
	printf 'current zshrc\n' >"$FAKE_ZSHRC"
	mkdir "$FAKE_ZSHRC.before-nix-darwin"
	printf 'keep this directory\n' >"$FAKE_ZSHRC.before-nix-darwin/keep"

	run_macos_installer

	[ "$status" -ne 0 ]
	grep -q '^stale bashrc backup$' "$FAKE_BASHRC.before-nix-darwin"
	[ -d "$FAKE_ZSHRC.before-nix-darwin" ]
	grep -q '^keep this directory$' "$FAKE_ZSHRC.before-nix-darwin/keep"
	grep -q '^current bashrc$' "$FAKE_BASHRC"
	grep -q '^current zshrc$' "$FAKE_ZSHRC"
	! grep -q '^sudo </bin/rm>' "$COMMAND_LOG"
	! grep -q '^sudo <mv>' "$COMMAND_LOG"
	! grep -q '^nix run .#darwin-rebuild -- switch' "$COMMAND_LOG"
}

@test "Docker link inspection recognizes only the exact current cask target" {
	local link="$FAKE_HOMEBREW_BIN_DIR/docker"
	local target="$FAKE_DOCKER_APP/Contents/Resources/bin/docker"
	local scenario expected
	mkdir -p "$FAKE_HOMEBREW_BIN_DIR"
	for scenario in missing current foreign; do
		rm -f "$link"
		case "$scenario" in
		missing) expected=missing ;;
		current)
			ln -s "$target" "$link"
			expected=current-cask
			;;
		foreign)
			ln -s "$TEST_HOMEBREW_LINK_TARGET/docker" "$link"
			expected=conflicting
			;;
		esac
		run bash -c '. "$INSTALLER"; docker_desktop_link_state "$1" "$2"' _ "$link" "$target"
		[ "$status" -eq 0 ]
		[ "$output" = "$expected" ]
	done
}

@test "running Docker Desktop is stopped when its engine is unavailable" {
	write_installed_stubs
	cat >"$FAKE_DOCKER_APP/Contents/Resources/bin/docker" <<'EOF'
#!/usr/bin/env bash
printf 'docker %s\n' "$*" >>"$COMMAND_LOG"
if [ "${1:-}" = "info" ] && ! grep -q 'nix run .#darwin-rebuild' "$COMMAND_LOG"; then
	exit 1
fi
EOF
	chmod +x "$FAKE_DOCKER_APP/Contents/Resources/bin/docker"

	run_macos_installer

	[ "$status" -eq 0 ]
	assert_log_order \
		"pgrep -x com.docker.backend" \
		"docker desktop stop --timeout 120" \
		"nix run .#darwin-rebuild -- switch --flake .#macos --impure"
}

@test "nix-darwin activation failure restores staged Docker cask links" {
	write_installed_stubs
	local docker_link="$FAKE_HOMEBREW_BIN_DIR/docker"
	local docker_target="$FAKE_DOCKER_APP/Contents/Resources/bin/docker"
	local compose_link="$FAKE_HOMEBREW_BIN_DIR/docker-compose"
	local compose_target="$FAKE_DOCKER_APP/Contents/Resources/cli-plugins/docker-compose"
	mkdir -p "$(dirname "$compose_target")"
	printf '#!/usr/bin/env bash\nexit 0\n' >"$compose_target"
	chmod +x "$compose_target"
	ln -s "$docker_target" "$docker_link"
	ln -s "$compose_target" "$compose_link"
	write_stub nix '
printf "nix %s\n" "$*" >>"$COMMAND_LOG"
if [[ ${1:-} == run ]]; then
	"$FAKE_DOCKER_CASK_ARTIFACT_INSTALLER"
	exit 42
fi
'

	run_macos_installer

	[ "$status" -eq 42 ]
	[ "$(/usr/bin/readlink "$docker_link")" = "$docker_target" ]
	[ "$(/usr/bin/readlink "$compose_link")" = "$compose_target" ]
	[ -x "$docker_link" ]
	[ -x "$compose_link" ]
	[ ! -e "$docker_link.dotfiles-cask-migration-backup" ]
	[ ! -L "$docker_link.dotfiles-cask-migration-backup" ]
	[ ! -e "$compose_link.dotfiles-cask-migration-backup" ]
	[ ! -L "$compose_link.dotfiles-cask-migration-backup" ]
}

@test "nix-darwin activation failure removes Docker cask links created from an all-missing state" {
	write_installed_stubs
	local -a managed_links=(
		"$FAKE_HOMEBREW_BIN_DIR/docker"
		"$FAKE_HOMEBREW_BIN_DIR/docker-compose"
		"$FAKE_HOMEBREW_BIN_DIR/docker-credential-desktop"
		"$FAKE_HOMEBREW_BIN_DIR/docker-credential-ecr-login"
		"$FAKE_HOMEBREW_BIN_DIR/docker-credential-osxkeychain"
		"$FAKE_HOMEBREW_BIN_DIR/kubectl"
		"$FAKE_HOMEBREW_BIN_DIR/kubectl.docker"
		"$FAKE_HOMEBREW_CLI_PLUGINS_DIR/docker-compose"
	)
	local link_path
	write_stub nix '
printf "nix %s\n" "$*" >>"$COMMAND_LOG"
if [[ ${1:-} == run ]]; then
	"$FAKE_DOCKER_CASK_ARTIFACT_INSTALLER"
	exit 42
fi
'

	run_macos_installer

	[ "$status" -eq 42 ]
	for link_path in "${managed_links[@]}"; do
		[ ! -e "$link_path" ]
		[ ! -L "$link_path" ]
	done
}

@test "nix-darwin activation failure restores staged links and removes partially created missing links" {
	write_installed_stubs
	local docker_link="$FAKE_HOMEBREW_BIN_DIR/docker"
	local docker_target="$FAKE_DOCKER_APP/Contents/Resources/bin/docker"
	local credential_link="$FAKE_HOMEBREW_BIN_DIR/docker-credential-desktop"
	local credential_target="$FAKE_DOCKER_APP/Contents/Resources/bin/docker-credential-desktop"
	local compose_link="$FAKE_HOMEBREW_CLI_PLUGINS_DIR/docker-compose"
	local compose_target="$FAKE_DOCKER_APP/Contents/Resources/cli-plugins/docker-compose"
	ln -s "$docker_target" "$docker_link"
	write_stub nix '
printf "nix %s\n" "$*" >>"$COMMAND_LOG"
if [[ ${1:-} == run ]]; then
	ln -s "$FAKE_DOCKER_APP/Contents/Resources/bin/docker" "$FAKE_HOMEBREW_BIN_DIR/docker"
	ln -s "$FAKE_DOCKER_APP/Contents/Resources/bin/docker-credential-desktop" \
		"$FAKE_HOMEBREW_BIN_DIR/docker-credential-desktop"
	ln -s "$FAKE_DOCKER_APP/Contents/Resources/cli-plugins/docker-compose" \
		"$FAKE_HOMEBREW_CLI_PLUGINS_DIR/docker-compose"
	exit 42
fi
'

	run_macos_installer

	[ "$status" -eq 42 ]
	[ "$(/usr/bin/readlink "$docker_link")" = "$docker_target" ]
	[ -x "$docker_link" ]
	[ ! -e "$credential_link" ]
	[ ! -L "$credential_link" ]
	[ ! -e "$compose_link" ]
	[ ! -L "$compose_link" ]
	[ ! -e "$docker_link.dotfiles-cask-migration-backup" ]
	[ ! -L "$docker_link.dotfiles-cask-migration-backup" ]
}

@test "new Docker cask registration stages unmanaged current links and creates official artifacts" {
	write_installed_stubs
	local -a links=(
		"$FAKE_HOMEBREW_BIN_DIR/docker"
		"$FAKE_HOMEBREW_BIN_DIR/docker-compose"
		"$FAKE_HOMEBREW_BIN_DIR/docker-credential-desktop"
		"$FAKE_HOMEBREW_BIN_DIR/docker-credential-ecr-login"
		"$FAKE_HOMEBREW_BIN_DIR/docker-credential-osxkeychain"
		"$FAKE_HOMEBREW_BIN_DIR/kubectl"
		"$FAKE_HOMEBREW_BIN_DIR/kubectl.docker"
		"$FAKE_HOMEBREW_CLI_PLUGINS_DIR/docker-compose"
	)
	local -a targets=(
		"$FAKE_DOCKER_APP/Contents/Resources/bin/docker"
		"$FAKE_DOCKER_APP/Contents/Resources/cli-plugins/docker-compose"
		"$FAKE_DOCKER_APP/Contents/Resources/bin/docker-credential-desktop"
		"$FAKE_DOCKER_APP/Contents/Resources/bin/docker-credential-ecr-login"
		"$FAKE_DOCKER_APP/Contents/Resources/bin/docker-credential-osxkeychain"
		"$FAKE_DOCKER_APP/Contents/Resources/bin/kubectl"
		"$FAKE_DOCKER_APP/Contents/Resources/bin/kubectl"
		"$FAKE_DOCKER_APP/Contents/Resources/cli-plugins/docker-compose"
	)
	local index
	for index in "${!links[@]}"; do
		ln -s "${targets[$index]}" "${links[$index]}"
	done

	run_macos_installer

	[ "$status" -eq 0 ]
	[ "$(readlink "$FAKE_HOMEBREW_BIN_DIR/docker")" = "$FAKE_DOCKER_APP/Contents/Resources/bin/docker" ]
	[ "$(readlink "$FAKE_HOMEBREW_BIN_DIR/docker-credential-desktop")" = "$FAKE_DOCKER_APP/Contents/Resources/bin/docker-credential-desktop" ]
	[ "$(readlink "$FAKE_HOMEBREW_BIN_DIR/docker-credential-ecr-login")" = "$FAKE_DOCKER_APP/Contents/Resources/bin/docker-credential-ecr-login" ]
	[ "$(readlink "$FAKE_HOMEBREW_BIN_DIR/docker-credential-osxkeychain")" = "$FAKE_DOCKER_APP/Contents/Resources/bin/docker-credential-osxkeychain" ]
	[ "$(readlink "$FAKE_HOMEBREW_BIN_DIR/kubectl.docker")" = "$FAKE_DOCKER_APP/Contents/Resources/bin/kubectl" ]
	[ "$(readlink "$FAKE_HOMEBREW_CLI_PLUGINS_DIR/docker-compose")" = "$FAKE_DOCKER_APP/Contents/Resources/cli-plugins/docker-compose" ]
	[ ! -e "$FAKE_HOMEBREW_BIN_DIR/docker-compose" ]
	[ ! -L "$FAKE_HOMEBREW_BIN_DIR/docker-compose" ]
	assert_log_order \
		"sudo </bin/mv> <-n> <--> <${links[0]}> <${links[0]}.dotfiles-cask-migration-backup>" \
		"nix run .#darwin-rebuild -- switch --flake .#macos --impure"
}

@test "installed Docker cask repairs missing required links and removes obsolete current compose link" {
	write_installed_stubs
	export DOCKER_CASK_STATE="$BATS_TEST_TMPDIR/docker-cask-installed"
	touch "$DOCKER_CASK_STATE"
	ln -s "$FAKE_DOCKER_APP/Contents/Resources/bin/docker-credential-desktop" "$FAKE_HOMEBREW_BIN_DIR/docker-credential-desktop"
	ln -s "$FAKE_DOCKER_APP/Contents/Resources/cli-plugins/docker-compose" "$FAKE_HOMEBREW_BIN_DIR/docker-compose"
	write_stub brew '
if [[ ${1:-} == list && ${2:-} == --cask && ${3:-} == --versions &&
	${4:-} == docker-desktop && -f $DOCKER_CASK_STATE ]]; then
	printf "docker-desktop 4.89.0\n"
	exit 0
fi
if [[ ${1:-} == reinstall && ${2:-} == --cask && ${3:-} == docker-desktop ]]; then
	printf "brew %s\n" "$*" >>"$COMMAND_LOG"
	"$FAKE_DOCKER_CASK_ARTIFACT_INSTALLER"
	exit 0
fi
exit 1
'

	run_macos_installer

	[ "$status" -eq 0 ]
	grep -Fqx 'brew reinstall --cask docker-desktop' "$COMMAND_LOG"
	[ "$(readlink "$FAKE_HOMEBREW_BIN_DIR/docker")" = "$FAKE_DOCKER_APP/Contents/Resources/bin/docker" ]
	[ "$(readlink "$FAKE_HOMEBREW_BIN_DIR/docker-credential-desktop")" = "$FAKE_DOCKER_APP/Contents/Resources/bin/docker-credential-desktop" ]
	[ "$(readlink "$FAKE_HOMEBREW_BIN_DIR/docker-credential-ecr-login")" = "$FAKE_DOCKER_APP/Contents/Resources/bin/docker-credential-ecr-login" ]
	[ "$(readlink "$FAKE_HOMEBREW_BIN_DIR/docker-credential-osxkeychain")" = "$FAKE_DOCKER_APP/Contents/Resources/bin/docker-credential-osxkeychain" ]
	[ "$(readlink "$FAKE_HOMEBREW_BIN_DIR/kubectl.docker")" = "$FAKE_DOCKER_APP/Contents/Resources/bin/kubectl" ]
	[ "$(readlink "$FAKE_HOMEBREW_CLI_PLUGINS_DIR/docker-compose")" = "$FAKE_DOCKER_APP/Contents/Resources/cli-plugins/docker-compose" ]
	[ ! -e "$FAKE_HOMEBREW_BIN_DIR/docker-compose" ]
	[ ! -L "$FAKE_HOMEBREW_BIN_DIR/docker-compose" ]
}

@test "installed Docker cask repairs links before a later environment verification failure" {
	write_installed_stubs
	export DOCKER_CASK_STATE="$BATS_TEST_TMPDIR/docker-cask-installed"
	touch "$DOCKER_CASK_STATE"
	write_stub brew '
if [[ ${1:-} == list && ${2:-} == --cask && ${3:-} == --versions &&
	${4:-} == docker-desktop && -f $DOCKER_CASK_STATE ]]; then
	printf "docker-desktop 4.89.0\n"
	exit 0
fi
if [[ ${1:-} == reinstall && ${2:-} == --cask && ${3:-} == docker-desktop ]]; then
	printf "brew %s\n" "$*" >>"$COMMAND_LOG"
	"$FAKE_DOCKER_CASK_ARTIFACT_INSTALLER"
	exit 0
fi
exit 1
'
	write_stub nix 'printf "nix %s\n" "$*" >>"$COMMAND_LOG"'
	write_stub verify-environment 'printf "verify-environment failure\n" >>"$COMMAND_LOG"; exit 61'

	run_macos_installer

	[ "$status" -eq 61 ]
	[ "$(readlink "$FAKE_HOMEBREW_BIN_DIR/docker")" = "$FAKE_DOCKER_APP/Contents/Resources/bin/docker" ]
	[ "$(readlink "$FAKE_HOMEBREW_BIN_DIR/docker-credential-desktop")" = "$FAKE_DOCKER_APP/Contents/Resources/bin/docker-credential-desktop" ]
	[ "$(readlink "$FAKE_HOMEBREW_BIN_DIR/docker-credential-ecr-login")" = "$FAKE_DOCKER_APP/Contents/Resources/bin/docker-credential-ecr-login" ]
	[ "$(readlink "$FAKE_HOMEBREW_BIN_DIR/docker-credential-osxkeychain")" = "$FAKE_DOCKER_APP/Contents/Resources/bin/docker-credential-osxkeychain" ]
	[ "$(readlink "$FAKE_HOMEBREW_BIN_DIR/kubectl.docker")" = "$FAKE_DOCKER_APP/Contents/Resources/bin/kubectl" ]
	[ "$(readlink "$FAKE_HOMEBREW_CLI_PLUGINS_DIR/docker-compose")" = "$FAKE_DOCKER_APP/Contents/Resources/cli-plugins/docker-compose" ]
	assert_log_order \
		"nix run .#darwin-rebuild -- switch --flake .#macos --impure" \
		"brew reinstall --cask docker-desktop"
}

@test "already-managed Docker cask rerun preserves exact official links without reinstall" {
	write_installed_stubs
	"$FAKE_DOCKER_CASK_ARTIFACT_INSTALLER"
	write_stub brew '
if [[ ${1:-} == list && ${2:-} == --cask && ${3:-} == --versions && ${4:-} == docker-desktop ]]; then
	printf "docker-desktop 4.89.0\n"
	exit 0
fi
if [[ ${1:-} == reinstall ]]; then
	printf "brew %s\n" "$*" >>"$COMMAND_LOG"
	exit 93
fi
exit 1
'

	run_macos_installer

	[ "$status" -eq 0 ]
	[ "$(readlink "$FAKE_HOMEBREW_BIN_DIR/docker")" = "$FAKE_DOCKER_APP/Contents/Resources/bin/docker" ]
	[ "$(readlink "$FAKE_HOMEBREW_BIN_DIR/docker-credential-desktop")" = "$FAKE_DOCKER_APP/Contents/Resources/bin/docker-credential-desktop" ]
	[ "$(readlink "$FAKE_HOMEBREW_BIN_DIR/docker-credential-ecr-login")" = "$FAKE_DOCKER_APP/Contents/Resources/bin/docker-credential-ecr-login" ]
	[ "$(readlink "$FAKE_HOMEBREW_BIN_DIR/docker-credential-osxkeychain")" = "$FAKE_DOCKER_APP/Contents/Resources/bin/docker-credential-osxkeychain" ]
	[ "$(readlink "$FAKE_HOMEBREW_BIN_DIR/kubectl.docker")" = "$FAKE_DOCKER_APP/Contents/Resources/bin/kubectl" ]
	[ "$(readlink "$FAKE_HOMEBREW_CLI_PLUGINS_DIR/docker-compose")" = "$FAKE_DOCKER_APP/Contents/Resources/cli-plugins/docker-compose" ]
	[ ! -L "$FAKE_HOMEBREW_BIN_DIR/docker-compose" ]
	! grep -q '^sudo </bin/rm>' "$COMMAND_LOG"
	! grep -q '^sudo </bin/mv>' "$COMMAND_LOG"
	! grep -q '^brew reinstall ' "$COMMAND_LOG"
}

@test "failed Docker cask repair preserves current links and restores obsolete compose link" {
	write_installed_stubs
	touch "$FAKE_DOCKER_CASK_STATE"
	local docker_link="$FAKE_HOMEBREW_BIN_DIR/docker"
	local docker_target="$FAKE_DOCKER_APP/Contents/Resources/bin/docker"
	local compose_link="$FAKE_HOMEBREW_BIN_DIR/docker-compose"
	local compose_target="$FAKE_DOCKER_APP/Contents/Resources/cli-plugins/docker-compose"
	local credential_link="$FAKE_HOMEBREW_BIN_DIR/docker-credential-desktop"
	ln -s "$docker_target" "$docker_link"
	ln -s "$compose_target" "$compose_link"
	write_stub nix 'printf "nix %s\n" "$*" >>"$COMMAND_LOG"'
	write_stub brew '
if [[ ${1:-} == list && ${2:-} == --cask && ${3:-} == --versions && ${4:-} == docker-desktop ]]; then
	printf "docker-desktop 4.89.0\n"
	exit 0
fi
if [[ ${1:-} == reinstall && ${2:-} == --cask && ${3:-} == docker-desktop ]]; then
	ln -s "$FAKE_DOCKER_APP/Contents/Resources/bin/docker-credential-desktop" "$FAKE_HOMEBREW_BIN_DIR/docker-credential-desktop"
	exit 43
fi
exit 1
'

	run_macos_installer

	[ "$status" -eq 43 ]
	[ "$(readlink "$docker_link")" = "$docker_target" ]
	[ "$(readlink "$compose_link")" = "$compose_target" ]
	[ ! -e "$credential_link" ]
	[ ! -L "$credential_link" ]
	[ ! -L "$compose_link.dotfiles-cask-migration-backup" ]
	! grep -q '^migrate-darwin-provider ' "$COMMAND_LOG"
}

@test "Docker rollback preserves a foreign replacement created during failed activation" {
	write_installed_stubs
	local docker_link="$FAKE_HOMEBREW_BIN_DIR/docker"
	local foreign_target="$TEST_HOMEBREW_LINK_TARGET/docker"
	write_stub nix '
printf "nix %s\n" "$*" >>"$COMMAND_LOG"
if [[ ${1:-} == run ]]; then
	ln -s "$TEST_HOMEBREW_LINK_TARGET/docker" "$FAKE_HOMEBREW_BIN_DIR/docker"
	exit 42
fi
'

	run_macos_installer

	[ "$status" -eq 42 ]
	[ "$(readlink "$docker_link")" = "$foreign_target" ]
	[[ "$output" == *"Refusing to remove Docker Desktop rollback conflict: $docker_link"* ]]
}

@test "Docker cask inspection error aborts before any link mutation" {
	write_installed_stubs
	local current_link="$FAKE_HOMEBREW_BIN_DIR/docker"
	local current_target="$FAKE_DOCKER_APP/Contents/Resources/bin/docker"
	ln -s "$current_target" "$current_link"
	write_stub brew '
if [[ ${1:-} == list && ${2:-} == --cask && ${3:-} == --versions && ${4:-} == docker-desktop ]]; then
	printf "registry unavailable\n" >&2
	exit 23
fi
exit 1
'

	run_macos_installer

	[ "$status" -ne 0 ]
	[[ "$output" == *"Unable to inspect Homebrew cask state for docker-desktop"* ]]
	[ "$(readlink "$current_link")" = "$current_target" ]
	! grep -q '^sudo </bin/rm>' "$COMMAND_LOG"
	! grep -q 'nix run .#darwin-rebuild -- switch' "$COMMAND_LOG"
}

@test "installed Docker cask rejects a foreign link without removing valid current links" {
	write_installed_stubs
	local valid_link="$FAKE_HOMEBREW_BIN_DIR/docker"
	local valid_target="$FAKE_DOCKER_APP/Contents/Resources/bin/docker"
	local conflict="$FAKE_HOMEBREW_CLI_PLUGINS_DIR/docker-compose"
	local conflict_target="$TEST_HOMEBREW_LINK_TARGET/docker-compose"
	ln -s "$valid_target" "$valid_link"
	ln -s "$conflict_target" "$conflict"
	write_stub brew '
if [[ ${1:-} == list && ${2:-} == --cask && ${3:-} == --versions && ${4:-} == docker-desktop ]]; then
	printf "docker-desktop 4.89.0\n"
	exit 0
fi
exit 1
'

	run_macos_installer

	[ "$status" -ne 0 ]
	[[ "$output" == *"Refusing to replace Docker Desktop link conflict: $conflict"* ]]
	[ "$(readlink "$valid_link")" = "$valid_target" ]
	[ "$(readlink "$conflict")" = "$conflict_target" ]
	! grep -q '^sudo </bin/rm>' "$COMMAND_LOG"
	! grep -q 'nix run .#darwin-rebuild -- switch' "$COMMAND_LOG"
}

@test "Docker Desktop link cleanup rejects wrong resource and traversal targets" {
	write_installed_stubs
	local conflict="$FAKE_HOMEBREW_BIN_DIR/docker"
	local scenario target
	for scenario in wrong-resource traversal; do
		rm -f "$conflict"
		case "$scenario" in
		wrong-resource) target="$FAKE_DOCKER_APP/Contents/Resources/bin/docker-compose" ;;
		traversal) target="$FAKE_DOCKER_APP/Contents/Resources/../../../../outside/docker" ;;
		esac
		ln -s "$target" "$conflict"
		: >"$COMMAND_LOG"

		run_macos_installer

		[ "$status" -ne 0 ]
		[[ "$output" == *"Refusing to replace Docker Desktop link conflict: $conflict"* ]]
		[ "$(readlink "$conflict")" = "$target" ]
		! grep -q 'nix run .#darwin-rebuild -- switch' "$COMMAND_LOG"
	done
}

@test "late Docker Desktop link conflict preserves earlier valid current links" {
	write_installed_stubs
	local first_link="$FAKE_HOMEBREW_BIN_DIR/docker"
	local last_link="$FAKE_HOMEBREW_CLI_PLUGINS_DIR/docker-compose"
	local first_target="$FAKE_DOCKER_APP/Contents/Resources/bin/docker"
	local last_target="$TEST_HOMEBREW_LINK_TARGET/docker-compose"
	ln -s "$first_target" "$first_link"
	ln -s "$last_target" "$last_link"

	run_macos_installer

	[ "$status" -ne 0 ]
	[[ "$output" == *"Refusing to replace Docker Desktop link conflict: $last_link"* ]]
	[ "$(readlink "$first_link")" = "$first_target" ]
	[ "$(readlink "$last_link")" = "$last_target" ]
	! grep -q '^sudo </bin/rm>' "$COMMAND_LOG"
}

@test "Docker Desktop link cleanup rejects regular files directories and foreign symlinks" {
	write_installed_stubs
	local conflict="$FAKE_HOMEBREW_BIN_DIR/docker"
	local scenario
	for scenario in regular-file directory foreign-symlink; do
		rm -rf "$conflict"
		case "$scenario" in
		regular-file) printf 'keep\n' >"$conflict" ;;
		directory) mkdir "$conflict" ;;
		foreign-symlink) ln -s "$TEST_HOMEBREW_LINK_TARGET/docker" "$conflict" ;;
		esac
		: >"$COMMAND_LOG"

		run_macos_installer

		[ "$status" -ne 0 ]
		[[ "$output" == *"Refusing to replace Docker Desktop link conflict: $conflict"* ]]
		[[ -e $conflict || -L $conflict ]]
		! grep -q 'nix run .#darwin-rebuild -- switch' "$COMMAND_LOG"
	done
}

@test "nix-darwin installation does not require chezmoi" {
	write_installed_stubs
	rm "$STUB_BIN/chezmoi"
	run_macos_installer
	[ "$status" -eq 0 ]
	! grep -q '^chezmoi ' "$COMMAND_LOG"
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
}

@test "fresh Hermes install provisions Nix then delegates apps to nix-darwin and the native desktop installer" {
	write_fresh_install_stubs
	rmdir "$FAKE_HOMEBREW_BIN_DIR" "$FAKE_HOMEBREW_CLI_PLUGINS_DIR"

	run_macos_installer

	[ "$status" -eq 0 ]
	grep -Fqx "sudo </bin/mkdir> <--> <$FAKE_HOMEBREW_BIN_DIR>" "$COMMAND_LOG"
	grep -Fqx "sudo </bin/mkdir> <--> <$FAKE_HOMEBREW_CLI_PLUGINS_DIR>" "$COMMAND_LOG"
	assert_log_order \
		"nix-installer install --no-confirm" \
		"nix run .#darwin-rebuild -- switch --flake .#macos --impure" \
		"task --dir $REPO_ROOT hermes:desktop:install"
	[ "$(grep -c 'nix-installer install --no-confirm' "$COMMAND_LOG")" -eq 1 ]
	! grep -q 'raw.githubusercontent.com/Homebrew/install' "$COMMAND_LOG"
	! grep -q 'brew install --cask' "$COMMAND_LOG"
	! grep -q '^docker-install ' "$COMMAND_LOG"
	! grep -q 'softwareupdate' "$COMMAND_LOG"
}

@test "fresh Docker profile allows nix-darwin to provision Homebrew" {
	write_fresh_install_stubs
	export DOTFILES_TEST_HOMEBREW_UNAVAILABLE=1
	rmdir "$FAKE_HOMEBREW_BIN_DIR" "$FAKE_HOMEBREW_CLI_PLUGINS_DIR"

	run_macos_installer

	[ "$status" -eq 0 ]
	[ "$(readlink "$FAKE_HOMEBREW_BIN_DIR/docker")" = "$FAKE_DOCKER_APP/Contents/Resources/bin/docker" ]
	[ "$(readlink "$FAKE_HOMEBREW_BIN_DIR/docker-credential-desktop")" = "$FAKE_DOCKER_APP/Contents/Resources/bin/docker-credential-desktop" ]
	[ "$(readlink "$FAKE_HOMEBREW_BIN_DIR/docker-credential-ecr-login")" = "$FAKE_DOCKER_APP/Contents/Resources/bin/docker-credential-ecr-login" ]
	[ "$(readlink "$FAKE_HOMEBREW_BIN_DIR/docker-credential-osxkeychain")" = "$FAKE_DOCKER_APP/Contents/Resources/bin/docker-credential-osxkeychain" ]
	[ "$(readlink "$FAKE_HOMEBREW_BIN_DIR/kubectl.docker")" = "$FAKE_DOCKER_APP/Contents/Resources/bin/kubectl" ]
	[ "$(readlink "$FAKE_HOMEBREW_CLI_PLUGINS_DIR/docker-compose")" = "$FAKE_DOCKER_APP/Contents/Resources/cli-plugins/docker-compose" ]
	[ ! -L "$FAKE_HOMEBREW_BIN_DIR/docker-compose" ]
	assert_log_order \
		"nix-installer install --no-confirm" \
		"nix run .#darwin-rebuild -- switch --flake .#macos --impure" \
		"docker-install --accept-license --user=test-user"
	[[ "$output" != *"Homebrew command is unavailable"* ]]
}

@test "fresh install tolerates Homebrew being absent before nix-darwin activation" {
	write_fresh_install_stubs
	export DOTFILES_TEST_HOMEBREW_UNAVAILABLE=1
	rmdir "$FAKE_HOMEBREW_BIN_DIR" "$FAKE_HOMEBREW_CLI_PLUGINS_DIR"

	run_macos_installer

	[ "$status" -eq 0 ]
	assert_log_order \
		"nix-installer install --no-confirm" \
		"nix run .#darwin-rebuild -- switch --flake .#macos --impure"
}

@test "macOS installer contains no imperative application installer fallback" {
	grep -q 'run .#darwin-rebuild -- switch --flake .#macos --impure' "$INSTALLER"
	! grep -q 'brew install --cask' "$INSTALLER"
	! grep -q 'desktop.docker.com/mac' "$INSTALLER"
}

@test "macOS installer enables 1Password desktop CLI integration" {
	grep -q 'OP_BIOMETRIC_UNLOCK_ENABLED' "$INSTALLER"
	grep -q 'export OP_BIOMETRIC_UNLOCK_ENABLED' "$INSTALLER"
}

@test "Docker runtime uses the Homebrew cask app and requires explicit license acceptance" {
	run env -u DOTFILES_DOCKER_APP_PATH bash -c '
. "$INSTALLER"
printf "%s\n" "$DOCKER_APP"
'
	[ "$status" -eq 0 ]
	[ "$output" = "/Applications/Docker.app" ]
	grep -q 'DOTFILES_ACCEPT_DOCKER_LICENSE' "$INSTALLER"
	grep -q 'requires DOTFILES_ACCEPT_DOCKER_LICENSE=1' "$INSTALLER"
	! grep -q 'desktop.docker.com/mac' "$INSTALLER"
}

@test "a checkout already at the dotfiles target is kept in place" {
	write_installed_stubs
	rm "$HOME/.dotfiles"
	mkdir -p \
		"$HOME/.dotfiles/scripts/sh" \
		"$HOME/.dotfiles/chezmoi" \
		"$HOME/.dotfiles/docker/hermes-service"
	cp "$INSTALLER" "$HOME/.dotfiles/scripts/sh/install-macos.sh"
	cp "$COMMON_INSTALLER" "$HOME/.dotfiles/scripts/sh/install-common.sh"
	cp "$REPO_ROOT/scripts/sh/codex-npm.sh" "$HOME/.dotfiles/scripts/sh/codex-npm.sh"
	cp "$REPO_ROOT/scripts/sh/install-display.sh" "$HOME/.dotfiles/scripts/sh/install-display.sh"
	cp "$REPO_ROOT/Taskfile.yml" "$HOME/.dotfiles/Taskfile.yml"
	cp -R "$REPO_ROOT/taskfiles" "$HOME/.dotfiles/taskfiles"
	touch \
		"$HOME/.dotfiles/flake.nix" \
		"$HOME/.dotfiles/docker/hermes-service/compose.yml"
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

@test "Docker runtime launches the cask app before its CLI plugins exist" {
	write_installed_stubs
	export DOCKER_GUI_STARTED="$BATS_TEST_TMPDIR/docker-gui-started"
	write_stub open '
printf "open %s\n" "$*" >>"$COMMAND_LOG"
[[ $# -eq 1 && $1 == "$FAKE_DOCKER_APP" ]] || exit 64
touch "$DOCKER_GUI_STARTED"
'
	cat >"$FAKE_DOCKER_APP/Contents/Resources/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf "docker %s\n" "$*" >>"$COMMAND_LOG"
case " $* " in
  *" desktop stop --timeout 120 "*) exit 0 ;;
  *" desktop start "*) exit 97 ;;
  *" info "*) [[ -f $DOCKER_GUI_STARTED ]] ;;
  *" compose version "*) [[ -f $DOCKER_GUI_STARTED ]] ;;
esac
EOF
	chmod +x "$FAKE_DOCKER_APP/Contents/Resources/bin/docker"

	run_macos_installer

	[ "$status" -eq 0 ]
	grep -Fqx "open $FAKE_DOCKER_APP" "$COMMAND_LOG"
	! grep -Fq 'docker desktop start' "$COMMAND_LOG"
	assert_log_order \
		"docker info" \
		"open $FAKE_DOCKER_APP" \
		"docker compose version"
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
	grep -Fqx "open $FAKE_DOCKER_APP" "$COMMAND_LOG"
	! grep -Fq 'docker desktop start' "$COMMAND_LOG"
}

@test "Docker engine probe bounds a hung Docker CLI process" {
	write_installed_stubs
	cat >"$STUB_BIN/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf "docker %s\n" "$*" >>"$COMMAND_LOG"
if [ "${1:-}" = "info" ]; then
	exec /bin/sleep 30
fi
EOF
	chmod +x "$STUB_BIN/docker"

	run "$REAL_TIMEOUT" 4 bash -c '
set -euo pipefail
. "$INSTALLER"
if docker_engine_is_ready; then
  exit 9
fi
printf "bounded\n"
'

	[ "$status" -eq 0 ]
	[ "$output" = "bounded" ]
	[ "$(grep -c '^docker info$' "$COMMAND_LOG")" -eq 1 ]
}

@test "Docker Compose version probe bounds a hung Docker CLI process" {
	write_installed_stubs
	cat >"$STUB_BIN/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf "docker %s\n" "$*" >>"$COMMAND_LOG"
if [[ ${1:-} == info ]]; then
	exit 0
fi
if [[ ${1:-} == compose && ${2:-} == version ]]; then
	exec /bin/sleep 30
fi
exit 0
EOF
	chmod +x "$STUB_BIN/docker"

	run "$REAL_TIMEOUT" 4 bash -c '
set -euo pipefail
export DOCKER_PROBE_TIMEOUT_SECONDS=2
. "$INSTALLER"
ensure_docker_desktop_md5_compatibility() {
  :
}
setup_docker_runtime
'

	[ "$status" -eq 1 ]
	[[ "$output" == *"Docker Compose CLI version probe failed."* ]]
	[ "$(grep -c '^docker info$' "$COMMAND_LOG")" -eq 1 ]
	[ "$(grep -c '^docker compose version$' "$COMMAND_LOG")" -eq 1 ]
}
