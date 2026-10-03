#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	MACOS_INSTALLER="$REPO_ROOT/scripts/sh/install-macos.sh"
	GUEST_HOME="$BATS_TEST_TMPDIR/guest"
	OS_PROFILE="$BATS_TEST_TMPDIR/os-profile"
	LEGACY_PROFILE="$GUEST_HOME/.local/state/dotfiles/tart-profile"
	mkdir -p "$GUEST_HOME/.local/bin" "$(dirname "$LEGACY_PROFILE")" "$OS_PROFILE/bin"
	ln -s /nix/store/legacy-dotfiles-tart-minimal "$LEGACY_PROFILE"
	for command in git chezmoi nvim node npm; do
		ln -s "$LEGACY_PROFILE/bin/$command" "$GUEST_HOME/.local/bin/$command"
		printf '#!/bin/sh\nexit 0\n' >"$OS_PROFILE/bin/$command"
		chmod +x "$OS_PROFILE/bin/$command"
	done
	export MACOS_INSTALLER GUEST_HOME OS_PROFILE
}

retire_profile() {
	run bash -c '. "$MACOS_INSTALLER"; retire_tart_cli_profile "$GUEST_HOME" "$OS_PROFILE"'
}

@test "legacy Tart CLI links retire after OS-managed replacements exist" {
	retire_profile

	[ "$status" -eq 0 ]
	for command in git chezmoi nvim node npm; do
		[ ! -L "$GUEST_HOME/.local/bin/$command" ]
		[ -x "$OS_PROFILE/bin/$command" ]
	done
	[ ! -L "$LEGACY_PROFILE" ]
	retire_profile
	[ "$status" -eq 0 ]
}

@test "Tart migration preserves unmanaged commands and unrelated symlinks" {
	rm "$GUEST_HOME/.local/bin/git" "$GUEST_HOME/.local/bin/node"
	printf 'unmanaged\n' >"$GUEST_HOME/.local/bin/git"
	ln -s "$OS_PROFILE/bin/node" "$GUEST_HOME/.local/bin/node"

	retire_profile

	[ "$status" -eq 0 ]
	[ "$(cat "$GUEST_HOME/.local/bin/git")" = unmanaged ]
	[ "$(readlink "$GUEST_HOME/.local/bin/node")" = "$OS_PROFILE/bin/node" ]
}

@test "missing OS replacement leaves all legacy Tart links intact" {
	rm "$OS_PROFILE/bin/npm"

	retire_profile

	[ "$status" -eq 1 ]
	for command in git chezmoi nvim node npm; do
		[ -L "$GUEST_HOME/.local/bin/$command" ]
	done
	[ -L "$LEGACY_PROFILE" ]
}

@test "Tart migration does not follow a symbolic command directory" {
	mv "$GUEST_HOME/.local/bin" "$GUEST_HOME/foreign-bin"
	ln -s "$GUEST_HOME/foreign-bin" "$GUEST_HOME/.local/bin"

	retire_profile

	[ "$status" -eq 1 ]
	[ -L "$GUEST_HOME/foreign-bin/git" ]
	[ -L "$LEGACY_PROFILE" ]
}

@test "Tart migration preserves a profile not created by the retired installer" {
	rm "$LEGACY_PROFILE"
	ln -s /nix/store/unmanaged-profile "$LEGACY_PROFILE"

	retire_profile

	[ "$status" -eq 0 ]
	[ "$(readlink "$LEGACY_PROFILE")" = /nix/store/unmanaged-profile ]
	[ -L "$GUEST_HOME/.local/bin/git" ]
}
