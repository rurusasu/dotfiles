#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "flake pins darwin homebrew and system manager inputs" {
	run grep -E 'nix-darwin|nix-homebrew|system-manager' "$REPO_ROOT/flake.nix"
	[ "$status" -eq 0 ]
	[ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -ge 3 ]
}

@test "flake imports locked platform runner apps" {
	grep -q './apps.nix' "$REPO_ROOT/nix/flakes/default.nix"
	grep -q 'darwin-rebuild' "$REPO_ROOT/nix/flakes/apps.nix"
	grep -q 'system-manager' "$REPO_ROOT/nix/flakes/apps.nix"
}

@test "runner app wrappers use locked package outputs" {
	grep -Fq 'inputs.nix-darwin.packages.${system}.darwin-rebuild' "$REPO_ROOT/nix/flakes/apps.nix"
	grep -Fq 'inputs.system-manager.packages.${system}.default' "$REPO_ROOT/nix/flakes/apps.nix"
	grep -Fq 'darwin-rebuild.program = lib.getExe' "$REPO_ROOT/nix/flakes/apps.nix"
	grep -Fq 'system-manager.program =' "$REPO_ROOT/nix/flakes/apps.nix"
	grep -Fq "lib.getExe' inputs.system-manager.packages" "$REPO_ROOT/nix/flakes/apps.nix"
	grep -Fq '"system-manager"' "$REPO_ROOT/nix/flakes/apps.nix"
}

@test "runner apps are guarded by their target platforms" {
	grep -Fq 'lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin' "$REPO_ROOT/nix/flakes/apps.nix"
	grep -Fq 'lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux' "$REPO_ROOT/nix/flakes/apps.nix"
}

@test "treefmt check keeps formatting enforcement without deprecated platform aliases" {
	treefmt="$REPO_ROOT/nix/flakes/treefmt.nix"

	grep -Fq 'build.check =' "$treefmt"
	grep -Fq 'treefmt --no-cache' "$treefmt"
	grep -Fq 'pkgs.stdenv.hostPlatform.isDarwin' "$treefmt"
	! grep -Fq 'pkgs.stdenv.isDarwin' "$treefmt"
}

@test "native NixOS output is unavailable without an explicit hardware profile" {
	grep -q 'DOTFILES_NIXOS_HARDWARE_CONFIG' "$REPO_ROOT/nix/flakes/hosts.nix"
	grep -q 'optionalAttrs.*hardwareConfig != ""' "$REPO_ROOT/nix/flakes/hosts.nix"
}

@test "flake outputs select canonical Home Manager OS modules" {
	grep -Fq 'homeModulePath = ../home/wsl.nix;' "$REPO_ROOT/nix/flakes/hosts.nix"
	grep -Fq 'homeModulePath = ../home/linux.nix;' "$REPO_ROOT/nix/flakes/hosts.nix"
	grep -Fq 'modules = [ ../home/darwin.nix ];' "$REPO_ROOT/nix/flakes/home.nix"
	grep -Fq 'modules = [ ../home/linux.nix ];' "$REPO_ROOT/nix/flakes/home.nix"
}

@test "NixOS applies the selected user's canonical WSL Home Manager module" {
	grep -Fq 'users.${user} = {' "$REPO_ROOT/nix/flakes/lib/hosts.nix"
	grep -Fq 'imports = [ homeModulePath ];' "$REPO_ROOT/nix/flakes/lib/hosts.nix"

	command -v nix >/dev/null 2>&1 || skip "nix is not available in this test environment"
	run --separate-stderr env DOTFILES_USER=nixos DOTFILES_HOME=/home/nixos DOTFILES_UID=1000 DOTFILES_GID=1000 DOTFILES_GROUP=nixos \
		nix eval --impure --raw --no-write-lock-file "path:$REPO_ROOT#nixosConfigurations.nixos.config.home-manager.users.nixos.programs.zsh.shellAliases.nrs"
	[ "$status" -eq 0 ]
	[ "$output" = 'task --dir ~/.dotfiles nrs' ]
}
