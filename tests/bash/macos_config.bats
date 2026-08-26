#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "latest nixpkgs flake evaluation excludes unsupported Intel macOS" {
	command -v nix >/dev/null 2>&1 || skip "nix is not available in this test environment"
	run nix flake show "path:$REPO_ROOT" --all-systems --json --no-write-lock-file
	[ "$status" -eq 0 ]
	[[ "$output" != *"x86_64-darwin"* ]]
}

@test "flake exposes a macOS nix-darwin configuration" {
	grep -q 'darwinConfigurations.macos' "$REPO_ROOT/nix/flakes/darwin.nix"
	grep -q './darwin.nix' "$REPO_ROOT/nix/flakes/default.nix"
}

@test "Darwin uses nix-homebrew catalog casks and Home Manager" {
	grep -q 'nix-homebrew = {' "$REPO_ROOT/nix/hosts/darwin/default.nix"
	grep -q 'casks = sets.darwinCasks' "$REPO_ROOT/nix/hosts/darwin/default.nix"
	grep -q 'home-manager.darwinModules.home-manager' "$REPO_ROOT/nix/flakes/darwin.nix"
}

@test "Darwin enables automatic Homebrew cask upgrades" {
	command -v nix >/dev/null 2>&1 || skip "nix is not available in this test environment"

	run --separate-stderr env DOTFILES_USER=codex DOTFILES_HOME=/Users/codex \
		nix eval --impure --json --expr "
			let config = (builtins.getFlake (toString $REPO_ROOT)).darwinConfigurations.macos.config;
			in {
				inherit (config.homebrew) greedyCasks;
				inherit (config.homebrew.onActivation) autoUpdate extraEnv upgrade;
			}
		"

	[ "$status" -eq 0 ]
	run jq -e '
		.autoUpdate == true and
		.greedyCasks == true and
		.upgrade == true and
		.extraEnv.HOMEBREW_AUTO_UPDATE_SECS == "86400" and
		.extraEnv.HOMEBREW_NO_ENV_HINTS == "1"
	' <<<"$output"
	[ "$status" -eq 0 ]
}

@test "Darwin passes Homebrew controls to the activation bundle" {
	command -v nix >/dev/null 2>&1 || skip "nix is not available in this test environment"

	run --separate-stderr env DOTFILES_USER=codex DOTFILES_HOME=/Users/codex \
		nix eval --impure --raw --expr "
			let
				config = (builtins.getFlake (toString $REPO_ROOT)).darwinConfigurations.macos.config;
			in config.system.activationScripts.homebrew.text
	"
	[ "$status" -eq 0 ]
	[[ "$output" == *'HOMEBREW_AUTO_UPDATE_SECS=86400'* ]]
	[[ "$output" == *'HOMEBREW_NO_ENV_HINTS=1'* ]]
	[[ "$output" != *'--no-upgrade'* ]]
}

@test "Darwin generates WezTerm nightly in the Homebrew Bundle" {
	command -v nix >/dev/null 2>&1 || skip "nix is not available in this test environment"

	run --separate-stderr env DOTFILES_USER=codex DOTFILES_HOME=/Users/codex \
		nix eval --impure --raw --no-write-lock-file --expr "
			let config = (builtins.getFlake (toString $REPO_ROOT)).darwinConfigurations.macos.config;
			in config.homebrew.brewfile
		"

	[ "$status" -eq 0 ]
	[[ "$output" == *'cask "wezterm@nightly", greedy: true'* ]]
}

@test "Darwin frees Command Space by disabling macOS launcher hotkeys" {
	local config="$REPO_ROOT/nix/hosts/darwin/default.nix"

	grep -qF 'system.defaults.CustomUserPreferences."com.apple.symbolichotkeys"' "$config"
	grep -qF 'AppleSymbolicHotKeys' "$config"
	for key in 60 61 64 65 156; do
		grep -qF "\"$key\" = {" "$config"
	done
	! grep -qF 'activationScripts.disableSpotlightHotkeys.text' "$config"
	! grep -q 'PlistBuddy' "$config"
	! grep -q 'com.raycast.macos' "$config"
	! grep -q 'open -gj -a Raycast' "$config"
}

@test "Darwin configures global Zoom shortcuts for English and Japanese menus" {
	local config="$REPO_ROOT/nix/hosts/darwin/default.nix"

	grep -qF 'activationScripts.globalZoomShortcut.text' "$config"
	grep -qF 'uid="$(id -u -- ${lib.escapeShellArg user})"' "$config"
	grep -qF 'runAsUser /usr/bin/defaults write -g NSUserKeyEquivalents -dict-add "Zoom" "@^m"' "$config"
	grep -qF 'runAsUser /usr/bin/defaults write -g NSUserKeyEquivalents -dict-add "拡大／縮小" "@^m"' "$config"
}

@test "Darwin omits the incompatible generated documentation" {
	grep -q 'documentation.enable = false' "$REPO_ROOT/nix/hosts/darwin/default.nix"
	grep -q 'tools.darwin-uninstaller.enable = false' "$REPO_ROOT/nix/hosts/darwin/default.nix"
}

@test "Home Manager accepts the bootstrap user and home environment" {
	grep -q 'DOTFILES_USER' "$REPO_ROOT/nix/home/common.nix"
	grep -q 'DOTFILES_HOME' "$REPO_ROOT/nix/home/common.nix"
}

@test "Darwin shells use Homebrew's 24-hour auto-update interval" {
	command -v nix >/dev/null 2>&1 || skip "nix is not available in this test environment"

	run --separate-stderr env DOTFILES_USER=codex DOTFILES_HOME=/Users/codex \
		nix eval --impure --raw --expr "
			let
				flake = builtins.getFlake (toString $REPO_ROOT);
			in flake.darwinConfigurations.macos.config.home-manager.users.codex.home.sessionVariables.HOMEBREW_AUTO_UPDATE_SECS
	"
	[ "$status" -eq 0 ]
	[ "$output" = "86400" ]
}

@test "Darwin uses Homebrew's renamed Ollama cask" {
	command -v nix >/dev/null 2>&1 || skip "nix is not available in this test environment"

	run --separate-stderr env DOTFILES_USER=codex DOTFILES_HOME=/Users/codex \
		nix eval --impure --json --expr "
			let
				config = (builtins.getFlake (toString $REPO_ROOT)).darwinConfigurations.macos.config;
			in config.homebrew.casks
	"
	[ "$status" -eq 0 ]
	run jq -e 'any(.[]; .name == "ollama-app") and all(.[]; .name != "ollama")' <<<"$output"
	[ "$status" -eq 0 ]
}

@test "Darwin declares the oMLX Homebrew formula" {
	command -v nix >/dev/null 2>&1 || skip "nix is not available in this test environment"

	run --separate-stderr env DOTFILES_USER=codex DOTFILES_HOME=/Users/codex \
		nix eval --impure --json --no-write-lock-file --expr "
			let config = (builtins.getFlake (toString $REPO_ROOT)).darwinConfigurations.macos.config;
			in config.homebrew.brews
		"

	[ "$status" -eq 0 ]
	run jq -e 'any(.[]; .name == "jundot/omlx/omlx")' <<<"$output"
	[ "$status" -eq 0 ]
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

@test "Darwin provisions GNU timeout for native Ollama" {
	grep -Fq 'pkgs.coreutils' "$REPO_ROOT/nix/home/common.nix"
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

@test "macOS devcontainer CI allows the cold start and full test suite to finish" {
	run awk '
		/name: E2E \(macOS\)/ { in_job = 1 }
		in_job && /timeout-minutes:/ { exit !($2 >= 60) }
		END { if (!in_job) exit 1 }
	' "$REPO_ROOT/.github/workflows/ci-devcontainer.yml"
	[ "$status" -eq 0 ]
}
