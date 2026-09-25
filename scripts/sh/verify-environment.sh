#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
COMPOSE_FILE="${DOTFILES_COMPOSE_FILE:-$ROOT/docker/hermes-service/compose.yml}"
runtime=0
nix_only=0

fail() {
  printf 'environment verification failed: %s\n' "$*" >&2
  exit 1
}

while (($# > 0)); do
  case "$1" in
  --runtime) runtime=1 ;;
  --nix-only) nix_only=1 ;;
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
)

case "$platform" in
darwin) required+=(brew darwin-rebuild) ;;
linux)
  required+=(systemctl)
  ((nix_only == 1)) || required+=(docker)
  [[ $system_layer == "nixos" ]] && required+=(nixos-rebuild)
  ;;
*) fail "unsupported verification platform: $platform" ;;
esac

if ((runtime == 1)); then
  required+=(docker)
fi

for command_name in "${required[@]}"; do
  command -v "$command_name" >/dev/null 2>&1 || fail "missing command: $command_name"
done

chezmoi apply --dry-run >/dev/null || fail "chezmoi dry-run failed"
if ! chezmoi verify --exclude=scripts >/dev/null; then
  chezmoi diff --exclude=scripts --no-pager --color=false >&2 || true
  fail "chezmoi target state differs"
fi

if { [[ $platform == "linux" ]] && ((nix_only == 0)); } || ((runtime == 1)); then
  [[ -f $COMPOSE_FILE ]] || fail "missing Compose file: $COMPOSE_FILE"
  docker compose version >/dev/null || fail "Docker Compose is unavailable"
  docker info >/dev/null || fail "Docker engine is unavailable"
fi

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
  if ((nix_only == 0)); then
    systemctl is-active --quiet docker.service || fail "Docker service is inactive"
    systemctl is-active --quiet docker.socket || fail "Docker socket is inactive"
  fi
fi

if ((nix_only == 1)) && [[ $platform == "linux" && ${DOTFILES_WITH_HERMES:-0} == "1" ]]; then
  command -v hermes >/dev/null 2>&1 || fail "missing native Hermes CLI: hermes"
  systemctl --user is-active --quiet hermes-agent.service ||
    fail "native Hermes user service is inactive: hermes-agent.service"
fi

if ((runtime == 1)); then
  docker run --rm hello-world >/dev/null || fail "Docker test container failed"
  docker compose -f "$COMPOSE_FILE" config >/dev/null || fail "Compose configuration is invalid"
  docker compose -f "$COMPOSE_FILE" ps --status running >/dev/null ||
    fail "Compose services are not running"
  expected_services="$(docker compose -f "$COMPOSE_FILE" config --format json |
    jq -r --arg profiles "${COMPOSE_PROFILES:-}" '
      ($profiles | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))) as $enabled_profiles
      | .services
      | to_entries[]
      | select(
          (.value.profiles // []) as $service_profiles
          | ($service_profiles | length) == 0 or
            any($service_profiles[]; . as $profile | $enabled_profiles | index($profile) != null)
        )
      | .key
    ' | LC_ALL=C sort)"
  running_services="$(docker compose -f "$COMPOSE_FILE" ps --status running --services | LC_ALL=C sort)"
  if [[ -z $expected_services || $running_services != "$expected_services" ]]; then
    printf 'Expected Compose services:\n%s\n' "${expected_services:-<none>}" >&2
    printf 'Running Compose services:\n%s\n' "${running_services:-<none>}" >&2
    fail "not all Compose services are running"
  fi
fi

printf 'Environment verification passed.\n'
