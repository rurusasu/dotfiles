#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	INSTALLER="$REPO_ROOT/scripts/sh/install-macos.sh"
	COMMON_INSTALLER="$REPO_ROOT/scripts/sh/install-common.sh"
	TEST_HOME="$BATS_TEST_TMPDIR/home"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"
	FAKE_DOCKER_APP="$BATS_TEST_TMPDIR/Docker.app"
	FAKE_NIX_PROFILE="$BATS_TEST_TMPDIR/nix-daemon.sh"
	FAKE_BASHRC="$BATS_TEST_TMPDIR/etc/bashrc"
	FAKE_ZSHRC="$BATS_TEST_TMPDIR/etc/zshrc"
	FAKE_USER_PROFILE_ROOT="$BATS_TEST_TMPDIR/etc/profiles/per-user"
	mkdir -p "$TEST_HOME" "$STUB_BIN"
	: >"$COMMAND_LOG"
	: >"$FAKE_NIX_PROFILE"

	export HOME="$TEST_HOME"
	export USER="test-user"
	export PATH="$STUB_BIN:/usr/bin:/bin"
	export COMMAND_LOG STUB_BIN
	export DOTFILES_DOCKER_APP_PATH="$FAKE_DOCKER_APP"
	export DOTFILES_DOCKER_SETUP_MARKER="$TEST_HOME/.config/dotfiles/docker-desktop-installed"
	export DOTFILES_NIX_PROFILE_SCRIPT="$FAKE_NIX_PROFILE"
	export DOTFILES_BASHRC_PATH="$FAKE_BASHRC"
	export DOTFILES_ZSHRC_PATH="$FAKE_ZSHRC"
	export DOTFILES_USER_PROFILE_ROOT="$FAKE_USER_PROFILE_ROOT"
	export DOTFILES_DOCKER_WAIT_ATTEMPTS=2
	export DOTFILES_SERVICE_WAIT_ATTEMPTS=2
	export DOTFILES_WAIT_SLEEP_SECONDS=0
	export DOTFILES_VERIFY_ENVIRONMENT="$STUB_BIN/verify-environment"

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
	write_stub sleep 'exit 0'
	write_stub date 'echo 20260717010203'
	write_stub sudo '
printf "sudo %s\n" "$*" >>"$COMMAND_LOG"
exec "$@"
'
	write_stub verify-environment 'printf "verify-environment %s\n" "$*" >>"$COMMAND_LOG"'
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

write_docker_app() {
	mkdir -p "$FAKE_DOCKER_APP/Contents/MacOS" "$FAKE_DOCKER_APP/Contents/Resources/bin"
	cat >"$FAKE_DOCKER_APP/Contents/MacOS/install" <<'EOF'
#!/usr/bin/env bash
printf 'docker-install %s\n' "$*" >>"$COMMAND_LOG"
EOF
	cat >"$FAKE_DOCKER_APP/Contents/Resources/bin/docker" <<'EOF'
#!/usr/bin/env bash
printf 'docker %s\n' "$*" >>"$COMMAND_LOG"
exit 0
EOF
	chmod +x \
		"$FAKE_DOCKER_APP/Contents/MacOS/install" \
		"$FAKE_DOCKER_APP/Contents/Resources/bin/docker"
}

write_installed_stubs() {
	write_docker_app
	mkdir -p "$(dirname "$DOTFILES_DOCKER_SETUP_MARKER")"
	touch "$DOTFILES_DOCKER_SETUP_MARKER"

	write_stub nix 'printf "nix %s\n" "$*" >>"$COMMAND_LOG"'
	write_stub chezmoi 'printf "chezmoi %s\n" "$*" >>"$COMMAND_LOG"'
	write_stub docker '
printf "docker %s\n" "$*" >>"$COMMAND_LOG"
exit 0
'
	ln -s "$REPO_ROOT" "$HOME/.dotfiles"
}

write_fresh_install_stubs() {
	write_stub curl '
printf "curl %s\n" "$*" >>"$COMMAND_LOG"
case "$*" in
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
exit 0
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

@test "installed prerequisites run nix-darwin chezmoi and Compose in order" {
	write_installed_stubs

	run "$INSTALLER"

	[ "$status" -eq 0 ]
	grep -q "^sudo /usr/bin/env .*DOTFILES_USER=test-user .* $STUB_BIN/nix run .#darwin-rebuild -- switch --flake .#macos --impure$" "$COMMAND_LOG"
	assert_log_order \
		"nix run .#darwin-rebuild -- switch --flake .#macos --impure" \
		"chezmoi init --source $REPO_ROOT/chezmoi" \
		"chezmoi apply --force" \
		"docker compose -f $REPO_ROOT/docker/hermes-agent/compose.yml config" \
		"docker compose -f $REPO_ROOT/docker/hermes-agent/compose.yml build --pull" \
		"docker compose -f $REPO_ROOT/docker/hermes-agent/compose.yml up -d --force-recreate --wait" \
		"verify-environment --runtime"
	! grep -q 'brew install --cask' "$COMMAND_LOG"
	! grep -q 'desktop.docker.com/mac' "$COMMAND_LOG"
	! grep -q 'docker-install' "$COMMAND_LOG"
}

@test "existing shell rc files are preserved before nix-darwin activation" {
	write_installed_stubs
	mkdir -p "$(dirname "$FAKE_BASHRC")"
	printf 'existing bashrc\n' >"$FAKE_BASHRC"
	printf 'existing zshrc\n' >"$FAKE_ZSHRC"

	run "$INSTALLER"

	[ "$status" -eq 0 ]
	[ ! -e "$FAKE_BASHRC" ]
	[ ! -e "$FAKE_ZSHRC" ]
	grep -q '^existing bashrc$' "$FAKE_BASHRC.before-nix-darwin"
	grep -q '^existing zshrc$' "$FAKE_ZSHRC.before-nix-darwin"
	assert_log_order \
		"sudo mv $FAKE_BASHRC $FAKE_BASHRC.before-nix-darwin" \
		"sudo mv $FAKE_ZSHRC $FAKE_ZSHRC.before-nix-darwin" \
		"nix run .#darwin-rebuild -- switch --flake .#macos --impure"
}

@test "running Docker Desktop is stopped before nix-darwin updates its cask" {
	write_installed_stubs

	run "$INSTALLER"

	[ "$status" -eq 0 ]
	assert_log_order \
		"docker info" \
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

	run "$INSTALLER"

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

	run "$INSTALLER"

	[ "$status" -eq 42 ]
	! grep -q '^chezmoi ' "$COMMAND_LOG"
	! grep -q '^docker compose ' "$COMMAND_LOG"
}

@test "fresh install provisions Nix then delegates apps and Rosetta to nix-darwin" {
	write_fresh_install_stubs

	run "$INSTALLER"

	[ "$status" -eq 0 ]
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
	touch \
		"$HOME/.dotfiles/flake.nix" \
		"$HOME/.dotfiles/docker/hermes-agent/compose.yml"
	INSTALLER="$HOME/.dotfiles/scripts/sh/install-macos.sh"

	run "$INSTALLER"

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

	run "$INSTALLER"

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

	run "$INSTALLER"

	[ "$status" -ne 0 ]
	[[ "$output" == *"Timed out waiting for Docker Desktop engine after 2 attempts."* ]]
	[ "$(grep -c '^docker info$' "$COMMAND_LOG")" -eq 4 ]
}
