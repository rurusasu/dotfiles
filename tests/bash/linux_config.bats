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

@test "System Manager shares the root nixpkgs input" {
  block="$(sed -n '/system-manager = {/,/^[[:space:]]*};/p' "$REPO_ROOT/flake.nix")"
  [[ "$block" == *'url = "github:numtide/system-manager"'* ]]
  [[ "$block" == *'inputs.nixpkgs.follows = "nixpkgs"'* ]]
}

@test "System Manager preserves the requested existing user identity" {
  grep -q 'mutableUsers = true' "$REPO_ROOT/nix/system-manager/default.nix"
  grep -q 'DOTFILES_UID' "$REPO_ROOT/nix/system-manager/default.nix"
  grep -q 'DOTFILES_GID' "$REPO_ROOT/nix/system-manager/default.nix"
  grep -q 'DOTFILES_GROUP' "$REPO_ROOT/nix/system-manager/default.nix"
  grep -q 'inherit uid home' "$REPO_ROOT/nix/system-manager/default.nix"
  grep -q 'group = primaryGroup' "$REPO_ROOT/nix/system-manager/default.nix"
}

@test "WSL rebuild alias delegates the full sequence to Taskfile" {
	grep -q 'nrs = "task --dir ~/.dotfiles nrs"' "$REPO_ROOT/nix/home/wsl.nix"
	grep -q '^  nrs:' "$REPO_ROOT/taskfiles/nix/taskfile.yml"
	grep -q 'task: hermes:bootstrap' "$REPO_ROOT/taskfiles/nix/taskfile.yml"
}

@test "Docker is activated by System Manager with a restricted group socket" {
  grep -q 'wantedBy = \[ "system-manager.target" \]' "$REPO_ROOT/nix/system-manager/docker.nix"
  grep -q 'SocketMode = "0660"' "$REPO_ROOT/nix/system-manager/docker.nix"
  grep -q 'SocketGroup = "docker"' "$REPO_ROOT/nix/system-manager/docker.nix"
}

@test "System Manager Ollama binds only to the Docker bridge gateway" {
  grep -q 'ip -4 -o addr show dev docker0' "$REPO_ROOT/nix/system-manager/ollama.nix"
  grep -q 'OLLAMA_HOST="$docker_gateway:11434"' "$REPO_ROOT/nix/system-manager/ollama.nix"
  ! grep -q '0.0.0.0:11434' "$REPO_ROOT/nix/system-manager/ollama.nix"
  grep -q 'host.docker.internal:host-gateway' "$REPO_ROOT/docker/hermes-agent/compose.yml"
}

@test "native NixOS rebuild alias keeps the hardware-safe installer path" {
	grep -q 'nrs = "~/.dotfiles/install.sh"' "$REPO_ROOT/nix/home/linux.nix"
}

@test "macOS rebuild alias keeps the application-safe installer path" {
	grep -q 'nrs = "~/.dotfiles/install.sh"' "$REPO_ROOT/nix/home/darwin.nix"
}
