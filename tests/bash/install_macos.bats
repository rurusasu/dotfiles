#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	INSTALLER="$REPO_ROOT/scripts/sh/install-macos.sh"
	TEST_HOME="$BATS_TEST_TMPDIR/home"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"
	FAKE_DOCKER_APP="$BATS_TEST_TMPDIR/Docker.app"
	FAKE_NIX_PROFILE="$BATS_TEST_TMPDIR/nix-daemon.sh"
	ACTIVATION="$BATS_TEST_TMPDIR/home-manager-generation"
	mkdir -p "$TEST_HOME" "$STUB_BIN" "$ACTIVATION"
	: >"$COMMAND_LOG"
	: >"$FAKE_NIX_PROFILE"

	export HOME="$TEST_HOME"
	export USER="test-user"
	export PATH="$STUB_BIN:/usr/bin:/bin"
	export COMMAND_LOG STUB_BIN ACTIVATION
	export DOTFILES_BREW_BIN="$STUB_BIN/brew"
	export DOTFILES_DOCKER_APP_PATH="$FAKE_DOCKER_APP"
	export DOTFILES_DOCKER_SETUP_MARKER="$TEST_HOME/.config/dotfiles/docker-desktop-installed"
	export DOTFILES_NIX_PROFILE_SCRIPT="$FAKE_NIX_PROFILE"
	export DOTFILES_DOCKER_WAIT_ATTEMPTS=2
	export DOTFILES_SERVICE_WAIT_ATTEMPTS=2
	export DOTFILES_WAIT_SLEEP_SECONDS=0

	cat >"$ACTIVATION/activate" <<'EOF'
#!/usr/bin/env bash
printf 'activate\n' >>"$COMMAND_LOG"
mkdir -p "$HOME/.nix-profile/bin"
if [ -n "${ACTIVATE_INSTALL_CHEZMOI:-}" ]; then
	cat >"$HOME/.nix-profile/bin/chezmoi" <<'STUB'
#!/usr/bin/env bash
printf 'chezmoi %s\n' "$*" >>"$COMMAND_LOG"
STUB
	chmod +x "$HOME/.nix-profile/bin/chezmoi"
fi
EOF
	chmod +x "$ACTIVATION/activate"

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

write_installed_stubs() {
	mkdir -p "$FAKE_DOCKER_APP/Contents/MacOS" "$FAKE_DOCKER_APP/Contents/Resources/bin"
	cat >"$FAKE_DOCKER_APP/Contents/MacOS/install" <<'EOF'
#!/usr/bin/env bash
printf 'docker-install %s\n' "$*" >>"$COMMAND_LOG"
EOF
	chmod +x "$FAKE_DOCKER_APP/Contents/MacOS/install"
	mkdir -p "$(dirname "$DOTFILES_DOCKER_SETUP_MARKER")"
	touch "$DOTFILES_DOCKER_SETUP_MARKER"

	write_stub pkgutil 'exit 0'
	write_stub softwareupdate 'printf "softwareupdate %s\n" "$*" >>"$COMMAND_LOG"'
	write_stub brew '
printf "brew %s\n" "$*" >>"$COMMAND_LOG"
if [ "${1:-}" = "shellenv" ]; then
	printf "export PATH=%q:\$PATH\n" "$STUB_BIN"
fi
'
	write_stub nix '
printf "nix %s\n" "$*" >>"$COMMAND_LOG"
if [ "${1:-}" = "build" ]; then
	printf "%s\n" "$ACTIVATION"
fi
'
	write_stub chezmoi 'printf "chezmoi %s\n" "$*" >>"$COMMAND_LOG"'
	write_stub docker '
printf "docker %s\n" "$*" >>"$COMMAND_LOG"
exit 0
'
	ln -s "$REPO_ROOT" "$HOME/.dotfiles"
}

write_fresh_install_stubs() {
	write_stub pkgutil 'exit 1'
	write_stub softwareupdate 'printf "softwareupdate %s\n" "$*" >>"$COMMAND_LOG"'
	write_stub curl '
case "$*" in
	*raw.githubusercontent.com/Homebrew/install*)
		cat <<'"'"'SCRIPT'"'"'
mkdir -p "$(dirname "$DOTFILES_BREW_BIN")"
cat >"$DOTFILES_BREW_BIN" <<'"'"'BREW'"'"'
#!/usr/bin/env bash
set -euo pipefail
printf "brew %s\n" "$*" >>"$COMMAND_LOG"
case "${1:-}" in
	shellenv)
		printf "export PATH=%q:\$PATH\n" "$(dirname "$DOTFILES_BREW_BIN")"
		;;
	install)
		mkdir -p "$DOTFILES_DOCKER_APP_PATH/Contents/MacOS" "$DOTFILES_DOCKER_APP_PATH/Contents/Resources/bin"
		cat >"$DOTFILES_DOCKER_APP_PATH/Contents/MacOS/install" <<'"'"'DOCKER_INSTALL'"'"'
#!/usr/bin/env bash
printf "docker-install %s\n" "$*" >>"$COMMAND_LOG"
DOCKER_INSTALL
		chmod +x "$DOTFILES_DOCKER_APP_PATH/Contents/MacOS/install"
		cat >"$DOTFILES_DOCKER_APP_PATH/Contents/Resources/bin/docker" <<'"'"'DOCKER'"'"'
#!/usr/bin/env bash
printf "docker %s\n" "$*" >>"$COMMAND_LOG"
exit 0
DOCKER
		chmod +x "$DOTFILES_DOCKER_APP_PATH/Contents/Resources/bin/docker"
		;;
esac
BREW
chmod +x "$DOTFILES_BREW_BIN"
SCRIPT
		;;
	*nixos.org/nix/install*)
		cat <<'"'"'SCRIPT'"'"'
printf "nix-installer %s\n" "$*" >>"$COMMAND_LOG"
cat >"$STUB_BIN/nix" <<'"'"'NIX'"'"'
#!/usr/bin/env bash
printf "nix %s\n" "$*" >>"$COMMAND_LOG"
if [ "${1:-}" = "build" ]; then
	printf "%s\n" "$ACTIVATION"
fi
NIX
chmod +x "$STUB_BIN/nix"
SCRIPT
		;;
	*) exit 2 ;;
esac
'
	export ACTIVATE_INSTALL_CHEZMOI=1
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

@test "installed prerequisites run Home Manager, chezmoi, and Compose in order without reinstalling" {
	write_installed_stubs

	run "$INSTALLER"

	[ "$status" -eq 0 ]
	assert_log_order \
		"nix build --no-link --print-out-paths .#homeConfigurations.aarch64-darwin.activationPackage --impure" \
		"activate" \
		"chezmoi init --source $REPO_ROOT/chezmoi" \
		"chezmoi apply --force" \
		"docker compose -f $REPO_ROOT/docker/hermes-agent/compose.yml config" \
		"docker compose -f $REPO_ROOT/docker/hermes-agent/compose.yml build --pull" \
		"docker compose -f $REPO_ROOT/docker/hermes-agent/compose.yml up -d --force-recreate --wait"
	! grep -q 'brew install' "$COMMAND_LOG"
	! grep -q 'softwareupdate' "$COMMAND_LOG"
	! grep -q 'docker-install' "$COMMAND_LOG"
	! grep -q 'docker desktop start' "$COMMAND_LOG"
}

@test "Home Manager build retries a transient Nix failure" {
	write_installed_stubs
	export DOTFILES_NIX_BUILD_ATTEMPTS=2
	export NIX_BUILD_COUNT_FILE="$BATS_TEST_TMPDIR/nix-build-count"
	write_stub nix '
printf "nix %s\n" "$*" >>"$COMMAND_LOG"
if [ "${1:-}" = "build" ]; then
	count=0
	if [ -f "$NIX_BUILD_COUNT_FILE" ]; then
		count="$(cat "$NIX_BUILD_COUNT_FILE")"
	fi
	count=$((count + 1))
	printf "%s\n" "$count" >"$NIX_BUILD_COUNT_FILE"
	if [ "$count" -eq 1 ]; then
		printf "transient cache failure\n" >&2
		exit 1
	fi
	printf "%s\n" "$ACTIVATION"
fi
'

	run "$INSTALLER"

	[ "$status" -eq 0 ]
	[ "$(cat "$NIX_BUILD_COUNT_FILE")" -eq 2 ]
}

@test "fresh install provisions Homebrew Docker Desktop Rosetta and Nix with required arguments" {
	write_fresh_install_stubs

	run "$INSTALLER"

	[ "$status" -eq 0 ]
	grep -q 'brew install --cask docker-desktop' "$COMMAND_LOG"
	grep -q 'sudo .* --accept-license --user=test-user' "$COMMAND_LOG"
	grep -q 'docker-install --accept-license --user=test-user' "$COMMAND_LOG"
	grep -q 'softwareupdate --install-rosetta --agree-to-license' "$COMMAND_LOG"
	grep -q 'nix-installer --daemon' "$COMMAND_LOG"
}

@test "Docker Desktop cask failure uses the checksum-verified DMG fallback" {
	write_installed_stubs
	rm -rf "$FAKE_DOCKER_APP"
	rm -f "$DOTFILES_DOCKER_SETUP_MARKER"
	export DOTFILES_DOCKER_FALLBACK_URL="https://example.test/Docker.dmg"
	printf 'verified docker dmg\n' >"$BATS_TEST_TMPDIR/fallback-source.dmg"
	export DOTFILES_DOCKER_FALLBACK_SHA256
	DOTFILES_DOCKER_FALLBACK_SHA256="$(
		shasum -a 256 "$BATS_TEST_TMPDIR/fallback-source.dmg" | awk '{print $1}'
	)"

	write_stub brew '
printf "brew %s\n" "$*" >>"$COMMAND_LOG"
if [ "${1:-}" = "shellenv" ]; then
	printf "export PATH=%q:\$PATH\n" "$STUB_BIN"
	exit 0
fi
exit 1
'
	write_stub curl '
printf "curl %s\n" "$*" >>"$COMMAND_LOG"
output=""
while [ "$#" -gt 0 ]; do
	if [ "$1" = "-o" ]; then
		shift
		output="$1"
	fi
	shift
done
cp "$BATS_TEST_TMPDIR/fallback-source.dmg" "$output"
'
	write_stub 7zz '
printf "7zz %s\n" "$*" >>"$COMMAND_LOG"
output=""
for arg in "$@"; do
	case "$arg" in
		-o*) output="${arg#-o}" ;;
	esac
done
app="$output/Docker/Docker.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/bin"
cat >"$app/Contents/MacOS/install" <<'"'"'INSTALL'"'"'
#!/usr/bin/env bash
printf "docker-install %s\n" "$*" >>"$COMMAND_LOG"
INSTALL
cat >"$app/Contents/Resources/bin/docker" <<'"'"'DOCKER'"'"'
#!/usr/bin/env bash
printf "docker %s\n" "$*" >>"$COMMAND_LOG"
exit 0
DOCKER
chmod +x "$app/Contents/MacOS/install" "$app/Contents/Resources/bin/docker"
'
	write_stub ditto '
printf "ditto %s\n" "$*" >>"$COMMAND_LOG"
cp -R "$1" "$2"
'
	write_stub codesign 'printf "codesign %s\n" "$*" >>"$COMMAND_LOG"'

	run "$INSTALLER"

	[ "$status" -eq 0 ]
	grep -q '^brew install --cask docker-desktop$' "$COMMAND_LOG"
	grep -q '^curl .*https://example.test/Docker.dmg.*-o ' "$COMMAND_LOG"
	grep -q '^7zz x -snld20 ' "$COMMAND_LOG"
	grep -q "^ditto .* $FAKE_DOCKER_APP$" "$COMMAND_LOG"
	grep -q "^codesign --verify --deep --strict $FAKE_DOCKER_APP$" "$COMMAND_LOG"
	grep -q '^docker-install --accept-license --user=test-user$' "$COMMAND_LOG"
}

@test "a checkout already at the dotfiles target is kept in place" {
	write_installed_stubs
	rm "$HOME/.dotfiles"
	mkdir -p \
		"$HOME/.dotfiles/scripts/sh" \
		"$HOME/.dotfiles/chezmoi" \
		"$HOME/.dotfiles/docker/hermes-agent"
	cp "$INSTALLER" "$HOME/.dotfiles/scripts/sh/install-macos.sh"
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
	write_stub docker '
printf "docker %s\n" "$*" >>"$COMMAND_LOG"
if [ "${1:-}" = "info" ]; then exit 1; fi
exit 0
'

	run "$INSTALLER"

	[ "$status" -ne 0 ]
	[[ "$output" == *"Timed out waiting for Docker Desktop engine after 2 attempts."* ]]
	[ "$(grep -c '^docker info$' "$COMMAND_LOG")" -eq 3 ]
}
