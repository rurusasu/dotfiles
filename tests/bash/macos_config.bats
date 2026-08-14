#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "latest nixpkgs flake evaluation excludes unsupported Intel macOS" {
	command -v nix >/dev/null 2>&1 || skip "nix is not available in this test environment"
	run nix flake show "$REPO_ROOT" --all-systems --json --no-write-lock-file
	[ "$status" -eq 0 ]
	[[ "$output" != *"x86_64-darwin"* ]]
}

@test "flake exposes a macOS nix-darwin configuration" {
	grep -q 'darwinConfigurations.macos' "$REPO_ROOT/nix/flakes/darwin.nix"
	grep -q './darwin.nix' "$REPO_ROOT/nix/flakes/default.nix"
}

@test "Darwin uses nix-homebrew catalog casks and Home Manager" {
	grep -q 'nix-homebrew = {' "$REPO_ROOT/nix/darwin/default.nix"
	grep -q 'builtins.filter (cask: cask != "wezterm@nightly") sets.darwinCasks' "$REPO_ROOT/nix/darwin/default.nix"
	grep -q 'activationScripts.postActivation.text' "$REPO_ROOT/nix/darwin/default.nix"
	grep -q 'home-manager.darwinModules.home-manager' "$REPO_ROOT/nix/flakes/darwin.nix"
}

@test "Darwin activation zaps an existing Arc cask" {
	grep -q 'builtins.readFile ../../scripts/sh/uninstall-arc-browser.sh' "$REPO_ROOT/nix/darwin/default.nix"
	grep -q '/usr/bin/sudo --user=' "$REPO_ROOT/nix/darwin/default.nix"
	grep -q 'company.thebrowser.Browser' "$REPO_ROOT/nix/darwin/default.nix"
	grep -q 'postActivation.text' "$REPO_ROOT/nix/darwin/default.nix"
}

@test "Darwin separates missing-cask installation from explicit greedy upgrades" {
	command -v nix >/dev/null 2>&1 || skip "nix is not available in this test environment"

	run --separate-stderr env DOTFILES_USER=codex DOTFILES_HOME=/Users/codex \
		nix eval --impure --json --expr "
			let config = (builtins.getFlake (toString $REPO_ROOT)).darwinConfigurations.macos.config;
			in {
				inherit (config.homebrew) greedyCasks;
				inherit (config.homebrew.onActivation) autoUpdate upgrade;
			}
		"

	[ "$status" -eq 0 ]
	run jq -e '
		.autoUpdate == true and
		.greedyCasks == true and
		.upgrade == false
	' <<<"$output"
	[ "$status" -eq 0 ]
}

@test "Darwin frees Command Space for Raycast by disabling Spotlight hotkey" {
	grep -q 'com.apple.symbolichotkeys' "$REPO_ROOT/nix/darwin/default.nix"
	grep -q 'PlistBuddy' "$REPO_ROOT/nix/darwin/default.nix"
	grep -q 'enabled bool false' "$REPO_ROOT/nix/darwin/default.nix"
	grep -q 'disableSymbolicHotKey 60' "$REPO_ROOT/nix/darwin/default.nix"
	grep -q 'disableSymbolicHotKey 61' "$REPO_ROOT/nix/darwin/default.nix"
	grep -q 'disableSymbolicHotKey 64' "$REPO_ROOT/nix/darwin/default.nix"
	grep -q 'disableSymbolicHotKey 65' "$REPO_ROOT/nix/darwin/default.nix"
	grep -q 'disableSymbolicHotKey 156' "$REPO_ROOT/nix/darwin/default.nix"
	grep -q 'com.raycast.macos' "$REPO_ROOT/nix/darwin/default.nix"
	grep -q 'raycastGlobalHotkey -string Command-49' "$REPO_ROOT/nix/darwin/default.nix"
	grep -q 'activateSettings -u' "$REPO_ROOT/nix/darwin/default.nix"
}

@test "Darwin omits the incompatible generated documentation" {
	grep -q 'documentation.enable = false' "$REPO_ROOT/nix/darwin/default.nix"
	grep -q 'tools.darwin-uninstaller.enable = false' "$REPO_ROOT/nix/darwin/default.nix"
}

@test "Home Manager accepts the bootstrap user and home environment" {
	grep -q 'DOTFILES_USER' "$REPO_ROOT/nix/home/common.nix"
	grep -q 'DOTFILES_HOME' "$REPO_ROOT/nix/home/common.nix"
}

@test "Home Manager exposes Apple Silicon package manager and Docker paths" {
	run awk '
		/sessionPath = \[/ { in_darwin=1 }
		in_darwin && /"\/opt\/homebrew\/bin"/ { bin=1 }
		in_darwin && /"\/opt\/homebrew\/sbin"/ { sbin=1 }
		in_darwin && /"\/Applications\/Docker\.app\/Contents\/Resources\/bin"/ { docker=1 }
		in_darwin && /\];/ { exit(bin && sbin && docker ? 0 : 1) }
		END { if (!in_darwin) exit 1 }
	' "$REPO_ROOT/nix/home/common.nix"
	[ "$status" -eq 0 ]
}

@test "Darwin zsh restores WezTerm terminfo after inherited Home Manager sentinels" {
	command -v nix >/dev/null 2>&1 || skip "nix is not available in this test environment"

	run --separate-stderr env DOTFILES_USER=codex DOTFILES_HOME=/Users/codex nix eval --impure --raw --expr "
		let
			flake = builtins.getFlake (toString $REPO_ROOT);
		in flake.darwinConfigurations.macos.config.home-manager.users.codex.programs.zsh.envExtra
	"
	[ "$status" -eq 0 ]
	[[ "$output" == *'TERMINFO_DIRS'* ]]
	[[ "$output" == *'/etc/profiles/per-user/'* ]]
}

@test "WezTerm provides Darwin terminfo before spawning shells" {
	local config="$REPO_ROOT/chezmoi/terminals/wezterm/wezterm.lua"

	run grep -F 'config.set_environment_variables.TERMINFO_DIRS' "$config"
	[ "$status" -eq 0 ]
	run grep -F 'os.getenv("TERMINFO_DIRS")' "$config"
	[ "$status" -eq 0 ]
	run grep -F '/etc/profiles/per-user/' "$config"
	[ "$status" -eq 0 ]
}

@test "Chromium Compose service follows the host platform" {
	run awk '
		/^  chromium:/ { in_chromium=1; next }
		in_chromium && /^  [A-Za-z0-9_-]+:/ { exit }
		in_chromium && /platform:/ { found=1 }
		END { exit(found ? 1 : 0) }
	' "$REPO_ROOT/docker/hermes-agent/compose.yml"
	[ "$status" -eq 0 ]
	run grep -F 'ARG TARGETARCH' "$REPO_ROOT/docker/hermes-browser/Dockerfile"
	[ "$status" -eq 0 ]
	run grep -F 'arm64)' "$REPO_ROOT/docker/hermes-browser/Dockerfile"
	[ "$status" -eq 0 ]
}

@test "README documents the one-command macOS installer" {
	run grep -F './install.sh' "$REPO_ROOT/README.md"
	[ "$status" -eq 0 ]
	run grep -F 'Docker Desktop' "$REPO_ROOT/README.md"
	[ "$status" -eq 0 ]
}

@test "devcontainer CI watches macOS installer files" {
	run grep -F '"install.sh"' "$REPO_ROOT/.github/workflows/ci-devcontainer.yml"
	[ "$status" -eq 0 ]
	run grep -F '"scripts/sh/install-macos.sh"' "$REPO_ROOT/.github/workflows/ci-devcontainer.yml"
	[ "$status" -eq 0 ]
}
