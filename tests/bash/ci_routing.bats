#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	PATHS_FILE="$BATS_TEST_TMPDIR/changed-paths.txt"
}

assert_routing() {
	local path="$1"
	local expected="$2"

	printf '%s\n' "$path" >"$PATHS_FILE"
	run python3 "$REPO_ROOT/scripts/python/detect_ci_changes.py" --paths-file "$PATHS_FILE"
	[ "$status" -eq 0 ]
	[ "$output" = "$expected" ]
}

@test "Linux-only paths enable only Linux and contract checks" {
	assert_routing \
		"scripts/sh/install-linux.sh" \
		'{"chezmoi": false, "contract": true, "darwin": false, "devcontainer": false, "hermes": false, "linux": true, "nix": false, "package_catalog": false, "windows": false, "wsl": false}'
}

@test "Darwin-only paths enable only Darwin and contract checks" {
	assert_routing \
		"scripts/sh/install-macos.sh" \
		'{"chezmoi": false, "contract": true, "darwin": true, "devcontainer": false, "hermes": false, "linux": false, "nix": false, "package_catalog": false, "windows": false, "wsl": false}'
}

@test "WSL and Windows paths enable both platform checks" {
	assert_routing \
		"scripts/sh/nixos-wsl-postinstall.sh" \
		'{"chezmoi": false, "contract": true, "darwin": false, "devcontainer": false, "hermes": false, "linux": false, "nix": true, "package_catalog": false, "windows": true, "wsl": true}'
}

@test "shared package paths enable every platform package contract" {
	assert_routing \
		"nix/packages/sets.nix" \
		'{"chezmoi": true, "contract": true, "darwin": true, "devcontainer": false, "hermes": false, "linux": true, "nix": true, "package_catalog": true, "windows": true, "wsl": true}'
}
