#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	TEST_HOME="$BATS_TEST_TMPDIR/home"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"
	EDIT_CAPTURE="$BATS_TEST_TMPDIR/item-edit.json"
	OP_TOKEN_CAPTURE="$BATS_TEST_TMPDIR/op-token.log"
	READY_ATTEMPT_FILE="$BATS_TEST_TMPDIR/ready-attempts"
	XAPI_TOKEN_ATTEMPT_FILE="$BATS_TEST_TMPDIR/xapi-token-attempts"
	COMPOSE_FILE="$BATS_TEST_TMPDIR/docker/hermes-service/compose file.yml"
	REAL_JQ="$(command -v jq)"
	REAL_PYTHON3="$(command -v python3)"
	export REAL_INSTALL_TASK="$(command -v task)"
	SECRET_MARKER="adapter-secret-marker"
	mkdir -p "$TEST_HOME/.hermes" "$STUB_BIN"
	: >"$COMMAND_LOG"
	: >"$OP_TOKEN_CAPTURE"
	printf '0\n' >"$READY_ATTEMPT_FILE"
	printf '0\n' >"$XAPI_TOKEN_ATTEMPT_FILE"
	mkdir -p "$(dirname "$COMPOSE_FILE")" "$BATS_TEST_TMPDIR/nix/modules/hermes-agent"
	cp "$REPO_ROOT/nix/modules/hermes-agent/manifest.yaml" \
		"$BATS_TEST_TMPDIR/nix/modules/hermes-agent/manifest.yaml"
	: >"$COMPOSE_FILE"

	export REPO_ROOT HOME="$TEST_HOME" PATH="$STUB_BIN:/usr/bin:/bin"
	unset DOTFILES_USER SUDO_USER
	unset OP_SERVICE_ACCOUNT_TOKEN
	export COMMAND_LOG EDIT_CAPTURE OP_TOKEN_CAPTURE READY_ATTEMPT_FILE XAPI_TOKEN_ATTEMPT_FILE COMPOSE_FILE REAL_JQ REAL_PYTHON3 SECRET_MARKER
	export OP_ITEM_JSON='{"id":"item-id","fields":[{"label":"credential","value":"adapter-secret-marker"}]}'
	export XAPI_OP_ITEM_JSON='{"id":"xapi-item","fields":[{"label":"X_API_CLIENT_ID","value":"xapi-client-id-marker"},{"label":"X_API_CLIENT_SECRET","value":"xapi-client-secret-marker"},{"label":"X_API_REFRESH_TOKEN","section":{"label":"Refresh Token"},"value":"xapi-refresh-token-marker"}]}'
	export XAPI_OAUTH_ITEM_JSON='{"id":"xapi-oauth-item","fields":[{"label":"X_API_REFRESH_TOKEN","value":"xapi-refresh-token-marker"}]}'
	export OP_FAIL_ITEM=""
	export OP_EDIT_STATUS=0
	export OP_DELAY_SECONDS=0
	export OP_READ_TOKEN='service-account-token'
	export OP_READ_DELAY_SECONDS=0
	export OP_READ_COMPLETION_FILE=""
	export API_READY_AFTER=1
	export HERMES_API_READY_ATTEMPTS=3
	export HERMES_API_READY_DELAY_SECONDS=0
	export HERMES_API_PROBE_TIMEOUT_SECONDS=1
	export XAPI_TOKEN_READY_AFTER=1
	export XAPI_TOKEN_FAILURE_KIND=auth
	export XAPI_TOKEN_FAILURE_STATUS=1
	export XAPI_ROTATED_REFRESH_TOKEN=""
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
			if [ "${8:-}" = --template ]; then
				cat "${9:?}" >"$EDIT_CAPTURE"
			else
				cat >"$EDIT_CAPTURE"
			fi
			exit "$OP_EDIT_STATUS"
		fi
		[ "${2:-}" = get ] || exit 2
		printf "%s\n" "${OP_SERVICE_ACCOUNT_TOKEN:-<unset>}" >>"$OP_TOKEN_CAPTURE"
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
if [ "${1:-}" != "compose" ]; then
	exit 1
fi
case " $* " in
  *" run --rm --no-deps --entrypoint /bin/sh xapi-mcp "*)
	attempt="$(cat "$XAPI_TOKEN_ATTEMPT_FILE")"
	attempt=$((attempt + 1))
	printf "%s\n" "$attempt" >"$XAPI_TOKEN_ATTEMPT_FILE"
	if ((attempt < XAPI_TOKEN_READY_AFTER)); then
		if [[ $XAPI_TOKEN_FAILURE_KIND == auth ]]; then
			printf "%s\n" "Error: no valid oauth2 token for app default: Auth Error: TokenNotFound (cause: oauth2 token not found)" >&2
			printf "%s\n" "Run: xurl auth oauth2" >&2
		else
			printf "%s\n" "Cannot connect to the Docker daemon." >&2
		fi
		exit "$XAPI_TOKEN_FAILURE_STATUS"
	fi
	if [[ -n ${XAPI_ROTATED_REFRESH_TOKEN:-} ]]; then
		sed -i.bak "s/refresh_token:.*/refresh_token: \"$XAPI_ROTATED_REFRESH_TOKEN\"/" "$HOME/.hermes/.xurl/auth.yml"
		rm -f "$HOME/.hermes/.xurl/auth.yml.bak"
	fi
	exit 0
	;;
  *" up -d --force-recreate "*)
    exit "$UP_STATUS"
    ;;
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
	write_stub timeout '
if [[ ${1:-} == --version ]]; then
	printf "timeout (GNU coreutils) 9.0\n"
	exit 0
fi
printf "timeout" >>"$COMMAND_LOG"
printf " <%s>" "$@" >>"$COMMAND_LOG"
printf "\n" >>"$COMMAND_LOG"
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

run_restart_sidecar() {
	local missing_command="${1:-}"
	if [[ -z $missing_command ]]; then
		run env HERMES_COMPOSE_FILE="$COMPOSE_FILE" bash "$REPO_ROOT/scripts/sh/hermes-xapi.sh" restart
		return
	fi
	run env DOTFILES_TEST_MISSING_COMMAND="$missing_command" bash -c '
set -euo pipefail
. "$REPO_ROOT/scripts/sh/install-common.sh"
. "$REPO_ROOT/scripts/sh/hermes-sidecar-common.sh"
if [[ -n ${DOTFILES_TEST_MISSING_COMMAND:-} ]]; then
  dotfiles_have() {
    [[ $1 != "$DOTFILES_TEST_MISSING_COMMAND" ]] && command -v "$1" >/dev/null 2>&1
  }
fi
dotfiles_hermes_require_xapi_tools
dotfiles_hermes_prepare_runtime_home
dotfiles_hermes_ensure_xapi_auth docker "$COMPOSE_FILE"
dotfiles_hermes_with_xapi_credentials_and_cache \
  docker compose -f "$COMPOSE_FILE" up -d --force-recreate xapi-mcp
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
	run_restart_sidecar
	[ "$status" -ne 0 ]
	! grep -q '<compose>' "$COMMAND_LOG"
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
		"$MOCK_REPO/docker/hermes-service" \
		"$MOCK_REPO/docker/local-ai-services" \
		"$MOCK_BIN" "$MOCK_DOCKER_APP/Contents/MacOS" \
		"$MOCK_DOCKER_APP/Contents/Resources/bin"
	MOCK_REPO="$(cd "$MOCK_REPO" && pwd -P)"
	cp "$REPO_ROOT/install.sh" "$MOCK_REPO/install.sh"
	cp "$REPO_ROOT/Taskfile.yml" "$MOCK_REPO/Taskfile.yml"
	cp -R "$REPO_ROOT/taskfiles" "$MOCK_REPO/taskfiles"
	cp "$REPO_ROOT/scripts/sh/install-common.sh" "$MOCK_REPO/scripts/sh/install-common.sh"
	cp "$REPO_ROOT/scripts/sh/codex-npm.sh" "$MOCK_REPO/scripts/sh/codex-npm.sh"
	cp "$REPO_ROOT/scripts/sh/install-display.sh" "$MOCK_REPO/scripts/sh/install-display.sh"
	for installer in install-macos.sh install-home-manager.sh install-nixos.sh; do
		cp "$REPO_ROOT/scripts/sh/$installer" "$MOCK_REPO/scripts/sh/$installer"
	done
	mv "$MOCK_REPO/scripts/sh/install-macos.sh" \
		"$MOCK_REPO/scripts/sh/install-macos-under-test.sh"
	cat >"$MOCK_REPO/scripts/sh/install-macos.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

export DOTFILES_TEST_SELECTED_INSTALLER="$0"
. "$(dirname "${BASH_SOURCE[0]}")/install-macos-under-test.sh"
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
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
EOF
	touch "$MOCK_REPO/flake.nix" \
		"$MOCK_REPO/docker/hermes-service/compose.yml" \
		"$MOCK_REPO/docker/local-ai-services/compose.yml"

	cat >"$MOCK_REPO/scripts/sh/verify-environment.sh" <<'EOF'
#!/usr/bin/env bash
printf 'verify-environment %s\n' "$*" >>"$COMMAND_LOG"
EOF
	chmod +x "$MOCK_REPO/install.sh" \
		"$MOCK_REPO/scripts/sh/install-macos.sh" \
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
	write_fixture_stub brew '
if [[ ${1:-} == list && ${2:-} == --cask && ${3:-} == --versions && ${4:-} == docker-desktop ]]; then
  printf "docker-desktop 4.89.0\\n"
  exit 0
fi
exit 1
'
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
if [[ ${1:-} == --accept-flake-config ]]; then
  shift
fi
printf "nix %s\\n" "$*" >>"$COMMAND_LOG"
if [[ ${1:-} == --extra-experimental-features ]]; then
  while [[ ${1:-} != --command ]]; do shift; done
  shift
  exec "$@"
fi
if [[ $* == *"builtins.currentSystem"* ]]; then
  printf "x86_64-linux"
elif [[ $* == *homeConfigurations*activationPackage* ]]; then
  printf "%s/home-manager-generation\\n" "$MOCK_REPO"
fi
'
	mkdir -p "$MOCK_REPO/home-manager-generation"
	cat >"$MOCK_REPO/home-manager-generation/activate" <<'EOF'
#!/usr/bin/env bash
printf 'home-manager-activate\n' >>"$COMMAND_LOG"
EOF
	chmod +x "$MOCK_REPO/home-manager-generation/activate"
	export MOCK_REPO
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
fixture_user="${SUDO_USER:-$USER}"
expected_nix_config="NIX_CONFIG=extra-experimental-features = nix-command flakes
accept-flake-config = true"
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
    if [[ $# -eq 12 && ${2:-} == "SUDO_USER=$fixture_user" &&
      ${3:-} == "$expected_nix_config" &&
      ${4:-} == "${PATH%%:*}/nix" && ${5:-} == --accept-flake-config &&
      ${6:-} == run && ${7:-} == .#darwin-rebuild && ${8:-} == -- &&
      ${9:-} == switch && ${10:-} == --flake && ${11:-} == .#macos &&
      ${12:-} == --impure ]]; then
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
	write_fixture_stub npm '
prefix="${NPM_CONFIG_PREFIX:-$HOME/.local/npm}"
mkdir -p "$prefix/bin"
printf "#!/usr/bin/env bash\\nexit 0\\n" >"$prefix/bin/codex"
chmod +x "$prefix/bin/codex"
'
	write_fixture_stub curl 'printf "curl %s\\n" "$*" >>"$COMMAND_LOG"'
	write_fixture_stub launchctl 'printf "launchctl %s\\n" "$*" >>"$COMMAND_LOG"'
	write_fixture_stub open 'printf "open %s\\n" "$*" >>"$COMMAND_LOG"'
	write_fixture_stub docker 'printf "docker %s\\n" "$*" >>"$COMMAND_LOG"'
	write_fixture_stub task '
printf "task %s\\n" "$*" >>"$COMMAND_LOG"
case " $* " in
  *" darwin:install "*) exec "$REAL_INSTALL_TASK" "$@" ;;
esac
'
	write_fixture_stub python3 '
if [[ ${1:-} == scripts/python/update_darwin_packages.py ]]; then
  printf "python3 %s\\n" "$*" >>"$COMMAND_LOG"
  exit 0
fi
exec "$REAL_PYTHON3" "$@"
'

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
	shift
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
		ln -s "$MOCK_DOCKER_APP/Contents/Resources/bin/docker" "$homebrew_bin_dir/docker"
		ln -s "$MOCK_DOCKER_APP/Contents/Resources/bin/docker-credential-desktop" "$homebrew_bin_dir/docker-credential-desktop"
		ln -s "$MOCK_DOCKER_APP/Contents/Resources/bin/docker-credential-ecr-login" "$homebrew_bin_dir/docker-credential-ecr-login"
		ln -s "$MOCK_DOCKER_APP/Contents/Resources/bin/docker-credential-osxkeychain" "$homebrew_bin_dir/docker-credential-osxkeychain"
		ln -s "$MOCK_DOCKER_APP/Contents/Resources/bin/kubectl" "$homebrew_bin_dir/kubectl.docker"
		ln -s "$MOCK_DOCKER_APP/Contents/Resources/cli-plugins/docker-compose" "$homebrew_cli_plugins_dir/docker-compose"
		;;
	linux)
		rm -f "$marker"
		export MOCK_UNAME_S=Linux MOCK_UNAME_M=x86_64
		MOCK_SELECTED_INSTALLER=install-home-manager.sh
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
		DOTFILES_BREW_COMMAND="$MOCK_BIN/brew" \
		DOTFILES_LAUNCHCTL_COMMAND="$MOCK_BIN/launchctl" \
		DOTFILES_ACCEPT_DOCKER_LICENSE=1 \
		DOTFILES_OPEN_COMMAND="$MOCK_BIN/open" \
		DOTFILES_TASK_COMMAND="$MOCK_BIN/task" \
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
		"$MOCK_REPO/install.sh" "$@"
}

@test "Unix installers do not hand off native Hermes to the Docker bootstrap" {
	local installer contents
	for installer in install-macos.sh install-home-manager.sh install-nixos.sh; do
		contents="$REPO_ROOT/scripts/sh/$installer"
		! grep -Fq 'hermes-sidecar-common.sh' "$contents"
		if [[ $installer == install-macos.sh ]]; then
			grep -Fq 'dotfiles_run_task hermes:desktop:install' "$contents"
			! grep -Fq 'hermes:bootstrap' "$contents"
			continue
		fi
		! grep -Fq 'hermes:bootstrap' "$contents"
		! grep -Fq 'hermes:docker:bootstrap' "$contents"
		! grep -Fq 'dotfiles_hermes_start_stack' "$contents"
	done
}

@test "hermes:bootstrap activates the Nix-managed Hermes profile" {
	local bootstrap_task
	bootstrap_task="$(awk '
		/^  hermes:bootstrap:$/ { in_task = 1 }
		in_task && /^  [^ ]/ && $0 !~ /^  hermes:bootstrap:/ { exit }
		in_task { print }
	' "$REPO_ROOT/taskfiles/hermes/taskfile.yml")"

	[[ "$bootstrap_task" == *'nixos-rebuild-with-user.sh switch --flake . --impure'* ]]
	[[ "$bootstrap_task" == *'task darwin:install'* ]]
	[[ "$bootstrap_task" != *'hermes:docker:bootstrap'* ]]
	[[ "$bootstrap_task" != *'docker compose'* ]]
}

@test "NixOS-WSL Hermes readiness requires every critical check" {
	local readiness_script required_checks
	readiness_script="$(<"$REPO_ROOT/scripts/powershell/ci/Invoke-NixosWslE2E.ps1")"
	required_checks='["state_db", "session_store", "config", "model", "disk", "gateway", "background_queues"]'

	[[ "$readiness_script" == *"$required_checks"* ]]
	[[ "$readiness_script" == *'type == "object" and .status == "ok"'* ]]
	[[ "$readiness_script" == *'all(.[]; .status == "ok")'* ]]
}

@test "install.sh routes each Unix installer through the Taskfile after chezmoi" {
	local platform task_line apply_line task_line_number verify_line expected_sudo_count target
	for platform in macos linux nixos; do
		: >"$COMMAND_LOG"
		if [[ $platform == macos ]]; then
			run_mocked_installer "$platform"
		else
			run_mocked_installer "$platform"
		fi

		if [[ $status -ne 0 ]]; then
			printf '%s installer failed:\n%s\n' "$platform" "$output" >&3
			false
		fi
		if [[ $platform == macos ]]; then
			task_line="task --dir $MOCK_REPO hermes:desktop:install"
		else
			task_line=""
		fi
		apply_line="$(grep -n -m 1 '^chezmoi apply --force$' "$COMMAND_LOG" | cut -d: -f1)"
		[ -n "$apply_line" ]
		if [[ -n $task_line ]]; then
			grep -Fxq "$task_line" "$COMMAND_LOG"
			task_line_number="$(grep -n -m 1 -F "$task_line" "$COMMAND_LOG" | cut -d: -f1)"
			[ "$task_line_number" -gt "$apply_line" ]
		else
			! grep -q 'hermes:bootstrap\|docker compose.*hermes' "$COMMAND_LOG"
			if [[ $platform == nixos ]]; then
				verify_line="$(grep -n -m 1 '^verify-environment ' "$COMMAND_LOG" | cut -d: -f1)"
				[ -n "$verify_line" ]
				[ "$verify_line" -gt "$apply_line" ]
			else
				grep -Fxq 'home-manager-activate' "$COMMAND_LOG"
			fi
		fi
		! grep -q '^unexpected nixos-rebuild$' "$COMMAND_LOG"
		if [[ $platform == macos ]]; then
			grep -Fxq 'docker info' "$COMMAND_LOG"
			grep -Fxq 'docker compose version' "$COMMAND_LOG"
			grep -Fxq "sudo </usr/bin/env> <SUDO_USER=test-user> <NIX_CONFIG=extra-experimental-features = nix-command flakes" "$COMMAND_LOG"
			grep -Fxq "accept-flake-config = true> <$MOCK_BIN/nix> <--accept-flake-config> <run> <.#darwin-rebuild> <--> <switch> <--flake> <.#macos> <--impure>" "$COMMAND_LOG"
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
. "$REPO_ROOT/scripts/sh/hermes-sidecar-common.sh"
printf "%s\n%s\n" "$(dotfiles_hermes_data_dir)" "$(dotfiles_hermes_browser_data_dir)"
dotfiles_hermes_prepare_runtime_home
'

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "$TEST_HOME/custom-data" ]
	[ "${lines[1]}" = "$TEST_HOME/custom-browser" ]
	[ -d "$TEST_HOME/custom-data/.xurl" ]
	[ -d "$TEST_HOME/custom-browser" ]
}

@test "X API up only recreates the current browser and MCP sidecars" {
	run env HERMES_COMPOSE_FILE="$COMPOSE_FILE" bash "$REPO_ROOT/scripts/sh/hermes-xapi.sh" up

	[ "$status" -eq 0 ]
	grep -Fq '<up> <-d> <--force-recreate> <chromium> <browser-mcp> <xapi-mcp>' "$COMMAND_LOG"
	! grep -q '<hermes>\|<hermes-bootstrap>\|<volume>' "$COMMAND_LOG"
}

@test "X API authentication forwards OAuth credentials to the sidecar" {
	run env HERMES_COMPOSE_FILE="$COMPOSE_FILE" bash "$REPO_ROOT/scripts/sh/hermes-xapi.sh" auth

	[ "$status" -eq 0 ]
	grep -Fq '<xapi-mcp>' "$COMMAND_LOG"
	grep -Fq 'xurl auth oauth2 --headless' "$COMMAND_LOG"
	! grep -q 'xapi-client-secret-marker\|service-account-token' "$COMMAND_LOG"
}

@test "uses the Hermes data directory for the default browser directory" {
	export HERMES_DATA_DIR="$TEST_HOME/custom-data"

	run bash -c '
set -euo pipefail
. "$REPO_ROOT/scripts/sh/install-common.sh"
. "$REPO_ROOT/scripts/sh/hermes-sidecar-common.sh"
dotfiles_hermes_browser_data_dir
'

	[ "$status" -eq 0 ]
	[ "$output" = "$TEST_HOME/custom-data/.browser" ]
}

@test "injects X API OAuth credentials from 1Password for explicit wrapper commands" {
	export XAPI_OP_ITEM_JSON='{"id":"xapi-item","fields":[{"label":"X_API_CLIENT_ID","value":"xapi-client-id-marker"},{"label":"X_API_CLIENT_SECRET","value":"xapi-client-secret-marker"}]}'
	printf 'OP_SERVICE_ACCOUNT_TOKEN=cached-token\n' >"$HOME/.hermes/.op.env"
	chmod 600 "$HOME/.hermes/.op.env"

	run bash -c '
set -euo pipefail
. "$REPO_ROOT/scripts/sh/install-common.sh"
. "$REPO_ROOT/scripts/sh/hermes-sidecar-common.sh"
dotfiles_hermes_with_xapi_credentials bash -c '"'"'printf "%s:%s\n" "$X_API_CLIENT_ID" "$X_API_CLIENT_SECRET"'"'"'
'

	[ "$status" -eq 0 ]
	[ "$output" = "xapi-client-id-marker:xapi-client-secret-marker" ]
	grep -q '^op <item> <get> <Hermes X API MCP> <--account> <my.1password.com> <--vault> <openclaw> <--format> <json>$' "$COMMAND_LOG"
	! grep -q 'xapi-client-secret-marker' "$COMMAND_LOG"
}

@test "initializes the service account cache for a standalone X API command" {
	run bash -c '
set -euo pipefail
. "$REPO_ROOT/scripts/sh/install-common.sh"
. "$REPO_ROOT/scripts/sh/hermes-sidecar-common.sh"
dotfiles_hermes_with_xapi_credentials bash -c '"'"'printf "%s:%s\n" "$X_API_CLIENT_ID" "$X_API_CLIENT_SECRET"'"'"'
'

	[ "$status" -eq 0 ]
	[ "$output" = "xapi-client-id-marker:xapi-client-secret-marker" ]
	grep -q '<read>' "$COMMAND_LOG"
	! grep -q '<signin>' "$COMMAND_LOG"
	grep -q '^op <item> <get> <Hermes X API MCP> ' "$COMMAND_LOG"
	[ "$(cat "$HOME/.hermes/.op.env")" = 'OP_SERVICE_ACCOUNT_TOKEN=service-account-token' ]
	[ "$(service_account_cache_mode)" = 600 ]
}

@test "uses a valid service account cache without a trailing newline" {
	printf 'OP_SERVICE_ACCOUNT_TOKEN=cached-token' >"$HOME/.hermes/.op.env"
	chmod 600 "$HOME/.hermes/.op.env"

	run bash -c '
set -euo pipefail
. "$REPO_ROOT/scripts/sh/install-common.sh"
. "$REPO_ROOT/scripts/sh/hermes-sidecar-common.sh"
dotfiles_hermes_with_xapi_credentials bash -c '"'"'printf "%s:%s\n" "$X_API_CLIENT_ID" "$X_API_CLIENT_SECRET"'"'"'
'

	[ "$status" -eq 0 ]
	[ "$output" = "xapi-client-id-marker:xapi-client-secret-marker" ]
	run grep -q '<read>' "$COMMAND_LOG"
	[ "$status" -eq 1 ]
	[ "$(cat "$OP_TOKEN_CAPTURE")" = cached-token ]
}

@test "syncs the X API refresh token into the local xurl cache before startup" {
	local xapi_lookup_count last_xapi_lookup up_line
	run_restart_sidecar

	[ "$status" -eq 0 ]
	[ "$(stat -c '%a' "$HOME/.hermes/.xurl/auth.yml" 2>/dev/null || stat -f '%Lp' "$HOME/.hermes/.xurl/auth.yml")" = 600 ]
	grep -q 'client_id: "xapi-client-id-marker"' "$HOME/.hermes/.xurl/auth.yml"
	grep -q 'client_secret: "xapi-client-secret-marker"' "$HOME/.hermes/.xurl/auth.yml"
	grep -q 'refresh_token: "xapi-refresh-token-marker"' "$HOME/.hermes/.xurl/auth.yml"
	xapi_lookup_count="$(grep -c '<Hermes X API MCP>' "$COMMAND_LOG")"
	[ "$xapi_lookup_count" -ge 2 ]
	last_xapi_lookup="$(grep -n '<Hermes X API MCP>' "$COMMAND_LOG" | tail -n 1 | cut -d: -f1)"
	up_line="$(grep -n '<up> <-d> <--force-recreate> <xapi-mcp>' "$COMMAND_LOG" | cut -d: -f1)"
	[ "$last_xapi_lookup" -lt "$up_line" ]
	! grep -q 'xapi-refresh-token-marker' "$COMMAND_LOG"
	! grep -q '<item> <edit>' "$COMMAND_LOG"
}

@test "validates the X API token before recreating the X API sidecars" {
	local probe_line up_line

	run_restart_sidecar

	[ "$status" -eq 0 ]
	[ "$(cat "$XAPI_TOKEN_ATTEMPT_FILE")" -eq 1 ]
	probe_line="$(grep -n '<run> <--rm> <--no-deps> <--entrypoint> </bin/sh> <xapi-mcp>' "$COMMAND_LOG" | tail -n 1 | cut -d: -f1)"
	up_line="$(grep -n '<up> <-d> <--force-recreate> <xapi-mcp>' "$COMMAND_LOG" | cut -d: -f1)"
	[ -n "$probe_line" ]
	[ "$probe_line" -lt "$up_line" ]
}

@test "replaces an invalid local X API token from 1Password and validates it once" {
	mkdir -p "$HOME/.hermes/.xurl"
	cat >"$HOME/.hermes/.xurl/auth.yml" <<'EOF'
apps:
  default:
    client_id: "stale-client-id"
    client_secret: "stale-client-secret"
    oauth2_tokens:
      default:
        type: oauth2
        oauth2:
          refresh_token: "stale-refresh-token"
default_app: default
EOF
	chmod 600 "$HOME/.hermes/.xurl/auth.yml"
	export XAPI_TOKEN_READY_AFTER=2

	run_restart_sidecar

	[ "$status" -eq 0 ]
	[ "$(cat "$XAPI_TOKEN_ATTEMPT_FILE")" -eq 2 ]
	grep -q 'client_id: "xapi-client-id-marker"' "$HOME/.hermes/.xurl/auth.yml"
	grep -q 'client_secret: "xapi-client-secret-marker"' "$HOME/.hermes/.xurl/auth.yml"
	grep -q 'refresh_token: "xapi-refresh-token-marker"' "$HOME/.hermes/.xurl/auth.yml"
	grep -q '<up> <-d> <--force-recreate>' "$COMMAND_LOG"
	! grep -q 'stale-refresh-token' "$COMMAND_LOG"
}

@test "stops before sidecar recreation when local and 1Password X API tokens are invalid" {
	mkdir -p "$HOME/.hermes/.xurl"
	cat >"$HOME/.hermes/.xurl/auth.yml" <<'EOF'
apps:
  default:
    oauth2_tokens:
      default:
        type: oauth2
        oauth2:
          refresh_token: "stale-refresh-token"
default_app: default
EOF
	chmod 600 "$HOME/.hermes/.xurl/auth.yml"
	export XAPI_TOKEN_READY_AFTER=99

	run_restart_sidecar

	[ "$status" -ne 0 ]
	[ "$(cat "$XAPI_TOKEN_ATTEMPT_FILE")" -eq 2 ]
	[[ "$output" == *"task hermes:xapi:setup"* ]]
	grep -q 'refresh_token: "stale-refresh-token"' "$HOME/.hermes/.xurl/auth.yml"
	! grep -q '<up> <-d> <--force-recreate>' "$COMMAND_LOG"
	! grep -q 'stale-refresh-token' "$COMMAND_LOG"
}

@test "does not replace the local X API cache after a Docker probe failure" {
	mkdir -p "$HOME/.hermes/.xurl"
	cat >"$HOME/.hermes/.xurl/auth.yml" <<'EOF'
apps:
  default:
    oauth2_tokens:
      default:
        type: oauth2
        oauth2:
          refresh_token: "local-refresh-token"
default_app: default
EOF
	chmod 600 "$HOME/.hermes/.xurl/auth.yml"
	export XAPI_TOKEN_READY_AFTER=99
	export XAPI_TOKEN_FAILURE_KIND=infrastructure
	export XAPI_TOKEN_FAILURE_STATUS=125

	run_restart_sidecar

	[ "$status" -eq 125 ]
	[ "$(cat "$XAPI_TOKEN_ATTEMPT_FILE")" -eq 1 ]
	grep -q 'refresh_token: "local-refresh-token"' "$HOME/.hermes/.xurl/auth.yml"
	[[ "$output" != *"task hermes:xapi:setup"* ]]
	! grep -q '<item> <edit>' "$COMMAND_LOG"
	! grep -q '<up> <-d> <--force-recreate>' "$COMMAND_LOG"
}

@test "syncs a refresh token rotated by a successful X API probe back to 1Password" {
	mkdir -p "$HOME/.hermes/.xurl"
	cat >"$HOME/.hermes/.xurl/auth.yml" <<'EOF'
apps:
  default:
    oauth2_tokens:
      default:
        type: oauth2
        oauth2:
          refresh_token: "local-refresh-token"
default_app: default
EOF
	chmod 600 "$HOME/.hermes/.xurl/auth.yml"
	export XAPI_ROTATED_REFRESH_TOKEN=rotated-refresh-token

	run_restart_sidecar

	[ "$status" -eq 0 ]
	jq -e '.fields[] | select(.label == "X_API_REFRESH_TOKEN") | .value == "rotated-refresh-token"' "$EDIT_CAPTURE" >/dev/null
	! grep -q 'rotated-refresh-token' "$COMMAND_LOG"
}

@test "keeps a successfully rotated local X API token when 1Password sync fails" {
	mkdir -p "$HOME/.hermes/.xurl"
	cat >"$HOME/.hermes/.xurl/auth.yml" <<'EOF'
apps:
  default:
    oauth2_tokens:
      default:
        type: oauth2
        oauth2:
          refresh_token: "local-refresh-token"
default_app: default
EOF
	chmod 600 "$HOME/.hermes/.xurl/auth.yml"
	export XAPI_ROTATED_REFRESH_TOKEN=rotated-refresh-token
	export OP_EDIT_STATUS=17

	run_restart_sidecar

	[ "$status" -eq 17 ]
	grep -q 'refresh_token: "rotated-refresh-token"' "$HOME/.hermes/.xurl/auth.yml"
	! grep -q 'refresh_token: "local-refresh-token"' "$HOME/.hermes/.xurl/auth.yml"
	! grep -q '<up> <-d> <--force-recreate>' "$COMMAND_LOG"
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

	run env HERMES_COMPOSE_FILE="$REPO_ROOT/docker/hermes-service/compose.yml" \
		bash "$REPO_ROOT/scripts/sh/hermes-xapi.sh" sync-token

	[ "$status" -eq 0 ]
	jq -e '.fields[] | select(.label == "X_API_REFRESH_TOKEN") | .value == "local-refresh-token-marker"' "$EDIT_CAPTURE" >/dev/null
	grep -q '<read>' "$COMMAND_LOG"
	! grep -q '<signin>' "$COMMAND_LOG"
	[ "$(cat "$HOME/.hermes/.op.env")" = 'OP_SERVICE_ACCOUNT_TOKEN=service-account-token' ]
	[ "$(cat "$OP_TOKEN_CAPTURE")" = 'service-account-token' ]
	! grep -q 'local-refresh-token-marker' "$COMMAND_LOG"
}

@test "sync-token updates the configured OAuth item" {
	export DOTFILES_HERMES_XAPI_OAUTH_ITEM='Hermes X API MCP OAuth'
	export XAPI_OAUTH_ITEM_JSON='{"id":"xapi-oauth-item","fields":[{"label":"X_API_REFRESH_TOKEN","section":{"label":"Refresh Token"},"value":"xapi-refresh-token-marker"}]}'
	mkdir -p "$HOME/.hermes/.xurl"
	cat >"$HOME/.hermes/.xurl/auth.yml" <<'EOF'
apps:
    default:
        oauth2_tokens:
            app-user:
                oauth2:
                    refresh_token: configured-item-refresh-token-marker
default_app: default
EOF
	chmod 600 "$HOME/.hermes/.xurl/auth.yml"

	run env HERMES_COMPOSE_FILE="$REPO_ROOT/docker/hermes-service/compose.yml" \
		bash "$REPO_ROOT/scripts/sh/hermes-xapi.sh" sync-token

	[ "$status" -eq 0 ]
	grep -q '<item> <get> <Hermes X API MCP OAuth>' "$COMMAND_LOG"
	grep -q '<item> <edit> <Hermes X API MCP OAuth>' "$COMMAND_LOG"
	jq -e '.fields[] | select(.label == "X_API_REFRESH_TOKEN") | .value == "configured-item-refresh-token-marker"' "$EDIT_CAPTURE" >/dev/null
}

@test "uses a mode-0600 cached service account without starting an op read" {
	printf 'OP_SERVICE_ACCOUNT_TOKEN=cached-token\n' >"$HOME/.hermes/.op.env"
	chmod 600 "$HOME/.hermes/.op.env"
	export OP_READ_COMPLETION_FILE="$BATS_TEST_TMPDIR/op-read-completed"
	export OP_READ_DELAY_SECONDS=2 DOTFILES_HERMES_OP_READ_TIMEOUT_SECONDS=1
	run_restart_sidecar
	[ "$status" -eq 0 ]
	[[ "$output" != *"using existing Hermes service-account environment"* ]]
	run grep -q '<read>' "$COMMAND_LOG"
	[ "$status" -eq 1 ]
	[ "$(cat "$HOME/.hermes/.op.env")" = 'OP_SERVICE_ACCOUNT_TOKEN=cached-token' ]
	[ "$(service_account_cache_mode)" = 600 ]
	/bin/sleep 2
	[ ! -e "$OP_READ_COMPLETION_FILE" ]
	[ "$(cat "$HOME/.hermes/.op.env")" = 'OP_SERVICE_ACCOUNT_TOKEN=cached-token' ]
	[ "$(service_account_cache_mode)" = 600 ]
}

@test "uses a valid cached service account for every host item read without desktop authorization" {
	local bootstrap_output
	printf 'OP_SERVICE_ACCOUNT_TOKEN=cached-token\n' >"$HOME/.hermes/.op.env"
	chmod 600 "$HOME/.hermes/.op.env"
	export OP_READ_TOKEN='unexpected-refresh-token'

	run_restart_sidecar

	[ "$status" -eq 0 ]
	bootstrap_output="$output"
	run grep -q '<read>' "$COMMAND_LOG"
	[ "$status" -eq 1 ]
	run grep -q '<signin>' "$COMMAND_LOG"
	[ "$status" -eq 1 ]
	[ -s "$OP_TOKEN_CAPTURE" ]
	run grep -vx 'cached-token' "$OP_TOKEN_CAPTURE"
	[ "$status" -eq 1 ]
	[[ "$bootstrap_output" != *'cached-token'* ]]
}

@test "rejects a writable cached service account after an op read timeout" {
	printf 'OP_SERVICE_ACCOUNT_TOKEN=cached-token\n' >"$HOME/.hermes/.op.env"
	chmod 644 "$HOME/.hermes/.op.env"
	export OP_READ_DELAY_SECONDS=2 DOTFILES_HERMES_OP_READ_TIMEOUT_SECONDS=1
	run_restart_sidecar
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
	grep -Fq 'timeout_seconds="${DOTFILES_HERMES_OP_READ_TIMEOUT_SECONDS:-20}"' "$REPO_ROOT/scripts/sh/hermes-sidecar-common.sh"
	grep -Fq '[[ $timeout_seconds =~ ^([1-9]|[1-9][0-9]|[12][0-9]{2}|300)$ ]] || timeout_seconds=20' "$REPO_ROOT/scripts/sh/hermes-sidecar-common.sh"
	export DOTFILES_HERMES_OP_READ_TIMEOUT_SECONDS=invalid
	run_restart_sidecar
	[ "$status" -eq 0 ]
}

@test "defaults service-account read timeouts above 300 seconds to twenty seconds" {
	grep -Fq '[[ $timeout_seconds =~ ^([1-9]|[1-9][0-9]|[12][0-9]{2}|300)$ ]] || timeout_seconds=20' "$REPO_ROOT/scripts/sh/hermes-sidecar-common.sh"
	export DOTFILES_HERMES_OP_READ_TIMEOUT_SECONDS=301
	run_restart_sidecar
	[ "$status" -eq 0 ]
}

@test "defaults arbitrarily large service-account read timeouts to twenty seconds" {
	export DOTFILES_HERMES_OP_READ_TIMEOUT_SECONDS=999999999999999999999999999999999999
	run bash -c '
set -euo pipefail
. "$REPO_ROOT/scripts/sh/install-common.sh"
. "$REPO_ROOT/scripts/sh/hermes-sidecar-common.sh"
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
	export DOTFILES_HERMES_REFRESH_SERVICE_ACCOUNT=1
	run_restart_sidecar
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
	export DOTFILES_HERMES_REFRESH_SERVICE_ACCOUNT=1
	run_restart_sidecar
	status=$status
	output=$output
	[ "$status" -ne 0 ]
	! grep -q '<compose>' "$COMMAND_LOG"
	[ "$(cat "$HOME/.hermes/.op.env")" = 'OP_SERVICE_ACCOUNT_TOKEN=old-token' ]
	[ "$(service_account_cache_mode)" = 600 ]
}

@test "fails preflight before Compose when op is unavailable" {
	run_restart_sidecar op

	[ "$status" -ne 0 ]
	[[ "$output" == *"1Password CLI (op) is required"* ]]
	[ ! -s "$COMMAND_LOG" ]
}

@test "fails preflight before Compose when jq is unavailable" {
	run_restart_sidecar jq

	[ "$status" -ne 0 ]
	[[ "$output" == *"jq is required"* ]]
	[ ! -s "$COMMAND_LOG" ]
}

@test "fails preflight before Compose when python3 is unavailable" {
	run_restart_sidecar python3

	[ "$status" -ne 0 ]
	[[ "$output" == *"python3 is required"* ]]
	[ ! -s "$COMMAND_LOG" ]
}
