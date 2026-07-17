#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "flake exposes Ubuntu and Debian System Manager configs" {
  grep -q 'ubuntu = mkConfig' "$REPO_ROOT/nix/flakes/system-manager.nix"
  grep -q 'debian = mkConfig' "$REPO_ROOT/nix/flakes/system-manager.nix"
}

@test "System Manager integrates Home Manager Nix and Docker" {
  grep -q 'home-manager.nixosModules.home-manager' "$REPO_ROOT/nix/flakes/system-manager.nix"
  grep -q 'nix.enable = true' "$REPO_ROOT/nix/system-manager/default.nix"
  grep -q 'services.docker' "$REPO_ROOT/nix/system-manager/docker.nix"
  grep -q 'sockets.docker' "$REPO_ROOT/nix/system-manager/docker.nix"
  grep -q 'docker-buildx' "$REPO_ROOT/nix/system-manager/docker.nix"
}

@test "System Manager preserves the requested existing user identity" {
  grep -q 'mutableUsers = true' "$REPO_ROOT/nix/system-manager/default.nix"
  grep -q 'DOTFILES_UID' "$REPO_ROOT/nix/system-manager/default.nix"
  grep -q 'DOTFILES_GID' "$REPO_ROOT/nix/system-manager/default.nix"
  grep -q 'DOTFILES_GROUP' "$REPO_ROOT/nix/system-manager/default.nix"
  grep -q 'inherit uid home' "$REPO_ROOT/nix/system-manager/default.nix"
  grep -q 'group = primaryGroup' "$REPO_ROOT/nix/system-manager/default.nix"
}

@test "Docker is activated by System Manager with a restricted group socket" {
  grep -q 'wantedBy = \[ "system-manager.target" \]' "$REPO_ROOT/nix/system-manager/docker.nix"
  grep -q 'SocketMode = "0660"' "$REPO_ROOT/nix/system-manager/docker.nix"
  grep -q 'SocketGroup = "docker"' "$REPO_ROOT/nix/system-manager/docker.nix"
}

@test "native NixOS rebuild alias keeps the hardware-safe installer path" {
	grep -q 'nrs = "~/.dotfiles/install.sh"' "$REPO_ROOT/nix/home/linux/users.nix"
}
