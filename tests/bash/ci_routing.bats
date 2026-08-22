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

assert_bootstrap_routing() {
	local path="$1"
	local expected="$2"

	printf '%s\n' "$path" >"$PATHS_FILE"
	run python3 "$REPO_ROOT/scripts/python/detect_ci_changes.py" \
		--manifest "$REPO_ROOT/ci/bootstrap-path-routing.json" \
		--paths-file "$PATHS_FILE"
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

@test "bootstrap Windows-only paths enable only Windows" {
	assert_bootstrap_routing \
		"windows/winget/packages.json" \
		'{"chezmoi": false, "contract": true, "darwin": false, "devcontainer": false, "hermes": false, "linux": false, "nix": false, "package_catalog": false, "windows": true, "wsl": false}'
}

@test "bootstrap Darwin-only paths enable only Darwin" {
	assert_bootstrap_routing \
		"nix/darwin/default.nix" \
		'{"chezmoi": false, "contract": true, "darwin": true, "devcontainer": false, "hermes": false, "linux": false, "nix": true, "package_catalog": false, "windows": false, "wsl": false}'
}

@test "bootstrap Linux-only paths enable only Linux" {
	assert_bootstrap_routing \
		"nix/hosts/linux/configuration.nix" \
		'{"chezmoi": false, "contract": true, "darwin": false, "devcontainer": false, "hermes": false, "linux": true, "nix": true, "package_catalog": false, "windows": false, "wsl": false}'
}

@test "bootstrap installer changes enable Linux and Darwin" {
	assert_bootstrap_routing \
		"install.sh" \
		'{"chezmoi": false, "contract": true, "darwin": true, "devcontainer": false, "hermes": false, "linux": true, "nix": false, "package_catalog": false, "windows": false, "wsl": false}'
}

@test "bootstrap WSL-only paths enable only WSL" {
	assert_bootstrap_routing \
		"nix/hosts/wsl/configuration.nix" \
		'{"chezmoi": false, "contract": true, "darwin": false, "devcontainer": false, "hermes": false, "linux": false, "nix": true, "package_catalog": false, "windows": false, "wsl": true}'
}

@test "bootstrap shared paths enable every platform" {
	assert_bootstrap_routing \
		"nix/packages/sets.nix" \
		'{"chezmoi": false, "contract": true, "darwin": true, "devcontainer": false, "hermes": false, "linux": true, "nix": true, "package_catalog": false, "windows": true, "wsl": true}'
}
