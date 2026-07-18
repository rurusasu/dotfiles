#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "latest nixpkgs flake evaluation excludes unsupported Intel macOS" {
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
	grep -q 'casks = sets.darwinCasks' "$REPO_ROOT/nix/darwin/default.nix"
	grep -q 'home-manager.darwinModules.home-manager' "$REPO_ROOT/nix/flakes/darwin.nix"
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
		/lib\.optionals pkgs\.stdenv\.isDarwin/ { in_darwin=1 }
		in_darwin && /"\/opt\/homebrew\/bin"/ { bin=1 }
		in_darwin && /"\/opt\/homebrew\/sbin"/ { sbin=1 }
		in_darwin && /"\/Applications\/Docker\.app\/Contents\/Resources\/bin"/ { docker=1 }
		in_darwin && /\];/ { exit(bin && sbin && docker ? 0 : 1) }
		END { if (!in_darwin) exit 1 }
	' "$REPO_ROOT/nix/home/common.nix"
	[ "$status" -eq 0 ]
}

@test "Chromium Compose service is pinned to linux amd64" {
	run awk '
		/^  chromium:/ { in_chromium=1; next }
		in_chromium && /^  [A-Za-z0-9_-]+:/ { exit }
		in_chromium && /platform: linux\/amd64/ { found=1 }
		END { exit(found ? 0 : 1) }
	' "$REPO_ROOT/docker/hermes-agent/compose.yml"
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
