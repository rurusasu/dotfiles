#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	INSTALLER="$REPO_ROOT/scripts/sh/hermes-desktop-install.sh"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"
	export PATH="$STUB_BIN:/usr/bin:/bin"
	export COMMAND_LOG
	export DOTFILES_HERMES_APP_PATH="$BATS_TEST_TMPDIR/Applications/Hermes.app"
	mkdir -p "$DOTFILES_HERMES_APP_PATH/Contents" "$STUB_BIN"
	touch "$DOTFILES_HERMES_APP_PATH/Contents/Info.plist"
	: >"$COMMAND_LOG"
}

write_stub() {
	local name="$1"
	local body="$2"
	{
		printf '#!/usr/bin/env bash\n'
		printf 'set -euo pipefail\n'
		printf '%s\n' "$body"
	} >"$STUB_BIN/$name"
	chmod +x "$STUB_BIN/$name"
}

@test "verifies the Nix-managed CLI and installed cask without invoking upstream setup" {
	write_stub hermes 'printf "hermes %s\\n" "$*" >>"$COMMAND_LOG"; printf "Hermes 0.21.0\\n"'
	write_stub open 'printf "open %s\\n" "$*" >>"$COMMAND_LOG"; exit 42'

	run "$INSTALLER"

	[ "$status" -eq 0 ]
	grep -Fqx 'hermes --version' "$COMMAND_LOG"
	! grep -q '^open ' "$COMMAND_LOG"
	[[ "$output" == *"Nix-managed Hermes Agent CLI is ready"* ]]
}

@test "fails when the nix-darwin Desktop cask is absent" {
	rm -rf "$DOTFILES_HERMES_APP_PATH"
	write_stub hermes 'printf "hermes %s\\n" "$*" >>"$COMMAND_LOG"; printf "Hermes 0.21.0\\n"'

	run "$INSTALLER"

	[ "$status" -ne 0 ]
	[[ "$output" == *"Hermes Desktop is not installed by the nix-darwin cask"* ]]
	[ ! -s "$COMMAND_LOG" ]
}

@test "fails when the Nix-managed Hermes CLI is unavailable" {
	run "$INSTALLER"

	[ "$status" -ne 0 ]
	[[ "$output" == *"Nix-managed Hermes Agent CLI is unavailable"* ]]
}
