#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
COMPOSE_FILE="${DOTFILES_COMPOSE_FILE:-$ROOT/docker/hermes-agent/compose.yml}"
runtime=0

fail() {
  printf 'environment verification failed: %s\n' "$*" >&2
  exit 1
}

while (($# > 0)); do
  case "$1" in
  --runtime) runtime=1 ;;
  *) fail "unknown argument: $1" ;;
  esac
  shift
done

platform="${DOTFILES_VERIFY_PLATFORM:-}"
system_layer="${DOTFILES_VERIFY_SYSTEM_LAYER:-system-manager}"
if [[ -z $platform ]]; then
  case "$(uname -s)" in
  Darwin) platform="darwin" ;;
  Linux) platform="linux" ;;
  *) fail "unsupported platform: $(uname -s)" ;;
  esac
fi

required=(
  nix
  git
  gh
  chezmoi
  rg
  fd
  jq
  nvim
  node
  python3
  go
  rustup
  docker
)

case "$platform" in
darwin) required+=(brew darwin-rebuild) ;;
linux)
  required+=(systemctl)
  [[ $system_layer == "nixos" ]] && required+=(nixos-rebuild)
  ;;
*) fail "unsupported verification platform: $platform" ;;
esac

for command_name in "${required[@]}"; do
  command -v "$command_name" >/dev/null 2>&1 || fail "missing command: $command_name"
done

[[ -f $COMPOSE_FILE ]] || fail "missing Compose file: $COMPOSE_FILE"
docker compose version >/dev/null || fail "Docker Compose is unavailable"
docker info >/dev/null || fail "Docker engine is unavailable"
chezmoi apply --dry-run >/dev/null || fail "chezmoi dry-run failed"
chezmoi verify >/dev/null || fail "chezmoi target state differs"

if [[ $platform == "linux" ]]; then
  case "$system_layer" in
  system-manager)
    systemctl is-active --quiet system-manager.target || fail "System Manager target is inactive"
    ;;
  nixos)
    current_system="${DOTFILES_CURRENT_SYSTEM_PATH:-/run/current-system}"
    [[ -e $current_system ]] || fail "NixOS current generation is missing: $current_system"
    ;;
  *) fail "unsupported Linux system layer: $system_layer" ;;
  esac
  systemctl is-active --quiet docker.service || fail "Docker service is inactive"
  systemctl is-active --quiet docker.socket || fail "Docker socket is inactive"
fi

if ((runtime == 1)); then
  docker run --rm hello-world >/dev/null || fail "Docker test container failed"
  docker compose -f "$COMPOSE_FILE" config >/dev/null || fail "Compose configuration is invalid"
  docker compose -f "$COMPOSE_FILE" ps --status running >/dev/null ||
    fail "Compose services are not running"
  expected_services="$(docker compose -f "$COMPOSE_FILE" config --services | LC_ALL=C sort)"
  running_services="$(docker compose -f "$COMPOSE_FILE" ps --status running --services | LC_ALL=C sort)"
  [[ -n $expected_services && $running_services == "$expected_services" ]] ||
    fail "not all Compose services are running"
fi

printf 'Environment verification passed.\n'
