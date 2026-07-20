#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
export DOTFILES_LOG_PREFIX="nixos-install"
# shellcheck source=/dev/null
. "$ROOT/scripts/sh/install-common.sh"
# shellcheck source=/dev/null
. "$ROOT/scripts/sh/hermes-agent.sh"

COMPOSE_FILE="${DOTFILES_COMPOSE_FILE:-$ROOT/docker/hermes-agent/compose.yml}"
NIXOS_MARKER="${DOTFILES_NIXOS_MARKER:-/etc/NIXOS}"
SERVICE_WAIT_ATTEMPTS="${DOTFILES_SERVICE_WAIT_ATTEMPTS:-60}"
VERIFY_ENVIRONMENT="${DOTFILES_VERIFY_ENVIRONMENT:-$ROOT/scripts/sh/verify-environment.sh}"
NIXOS_HARDWARE_CONFIG="${DOTFILES_NIXOS_HARDWARE_CONFIG:-/etc/nixos/hardware-configuration.nix}"
NIXOS_PREBUILT_SYSTEM="${DOTFILES_NIXOS_PREBUILT_SYSTEM:-}"

preflight() {
  [[ $(uname -s) == "Linux" && -e $NIXOS_MARKER ]] || dotfiles_die "NixOS is required."
  dotfiles_have nix || dotfiles_die "Nix is required on NixOS."
  dotfiles_have nixos-rebuild || dotfiles_die "nixos-rebuild is required on NixOS."

  [[ $NIXOS_HARDWARE_CONFIG == /* ]] ||
    dotfiles_die "NixOS hardware configuration must be an absolute path: $NIXOS_HARDWARE_CONFIG"
  [[ -r $NIXOS_HARDWARE_CONFIG ]] ||
    dotfiles_die "NixOS hardware configuration is missing or unreadable: $NIXOS_HARDWARE_CONFIG"
  if [[ -n $NIXOS_PREBUILT_SYSTEM ]]; then
    [[ $NIXOS_PREBUILT_SYSTEM == /* ]] ||
      dotfiles_die "Prebuilt NixOS system must be an absolute path: $NIXOS_PREBUILT_SYSTEM"
    [[ -x $NIXOS_PREBUILT_SYSTEM/bin/switch-to-configuration ]] ||
      dotfiles_die "Prebuilt NixOS system is invalid: $NIXOS_PREBUILT_SYSTEM"
  fi

  local required
  for required in \
    "$ROOT/flake.nix" \
    "$ROOT/chezmoi" \
    "$COMPOSE_FILE" \
    "$VERIFY_ENVIRONMENT"; do
    [[ -e $required ]] || dotfiles_die "Required repository path is missing: $required"
  done
}

capture_host_identity() {
  export DOTFILES_USER="${SUDO_USER:-${USER:-}}"
  export DOTFILES_HOME="$HOME"
  [[ -n $DOTFILES_USER && $DOTFILES_HOME == /* ]] ||
    dotfiles_die "A current user and absolute home directory are required."

  DOTFILES_UID="$(id -u "$DOTFILES_USER")"
  DOTFILES_GID="$(id -g "$DOTFILES_USER")"
  DOTFILES_GROUP="$(id -gn "$DOTFILES_USER")"
  export DOTFILES_UID DOTFILES_GID DOTFILES_GROUP
  [[ $DOTFILES_UID =~ ^[0-9]+$ && $DOTFILES_GID =~ ^[0-9]+$ && -n $DOTFILES_GROUP ]] ||
    dotfiles_die "The existing user must have numeric UID/GID values."

  export DOTFILES_SYSTEM
  DOTFILES_SYSTEM="$(nix eval --impure --raw --expr builtins.currentSystem)"
  case "$DOTFILES_SYSTEM" in
  x86_64-linux | aarch64-linux) ;;
  *) dotfiles_die "Unsupported NixOS system: $DOTFILES_SYSTEM" ;;
  esac
}

apply_nixos_system() {
  if [[ -n $NIXOS_PREBUILT_SYSTEM ]]; then
    dotfiles_log "Activating prebuilt NixOS system for E2E..."
    sudo "$NIXOS_PREBUILT_SYSTEM/bin/switch-to-configuration" switch
    export PATH="/run/current-system/sw/bin:/etc/profiles/per-user/$DOTFILES_USER/bin:$HOME/.nix-profile/bin:$HOME/.local/state/nix/profile/bin:$PATH"
    hash -r
    return
  fi

  local rebuild_bin
  rebuild_bin="$(command -v nixos-rebuild)"
  dotfiles_log "Applying NixOS and Home Manager..."
  sudo /usr/bin/env \
    "NIX_CONFIG=extra-experimental-features = nix-command flakes" \
    "DOTFILES_USER=$DOTFILES_USER" \
    "DOTFILES_HOME=$DOTFILES_HOME" \
    "DOTFILES_UID=$DOTFILES_UID" \
    "DOTFILES_GID=$DOTFILES_GID" \
    "DOTFILES_GROUP=$DOTFILES_GROUP" \
    "DOTFILES_SYSTEM=$DOTFILES_SYSTEM" \
    "DOTFILES_NIXOS_HARDWARE_CONFIG=$NIXOS_HARDWARE_CONFIG" \
    "$rebuild_bin" switch --flake "$ROOT#linux" --impure

  export PATH="/run/current-system/sw/bin:/etc/profiles/per-user/$DOTFILES_USER/bin:$HOME/.nix-profile/bin:$HOME/.local/state/nix/profile/bin:$PATH"
  hash -r
}

apply_chezmoi() {
  dotfiles_have chezmoi || dotfiles_die "chezmoi is unavailable after NixOS activation."
  chezmoi init --source "$ROOT/chezmoi"
  chezmoi apply --force
}

docker_command() {
  dotfiles_run_in_group docker docker "$@"
}

show_compose_diagnostics() {
  docker_command compose -f "$COMPOSE_FILE" ps || true
  docker_command compose -f "$COMPOSE_FILE" logs --tail=100 || true
}

start_hermes_stack() {
  dotfiles_log "Preparing Hermes runtime home..."
  dotfiles_hermes_prepare_runtime_home
  dotfiles_log "Validating Hermes Docker Compose configuration..."
  docker_command compose -f "$COMPOSE_FILE" config
  dotfiles_log "Building Hermes images..."
  docker_command compose -f "$COMPOSE_FILE" build --pull
  dotfiles_log "Ensuring Hermes dashboard auth..."
  dotfiles_hermes_ensure_dashboard_auth docker_command
  dotfiles_log "Ensuring Hermes runtime configuration..."
  dotfiles_hermes_ensure_runtime_configuration
  dotfiles_log "Ensuring Hermes Slack environment..."
  dotfiles_hermes_ensure_slack_environment
  dotfiles_log "Starting Hermes services..."
  if ! docker_command compose -f "$COMPOSE_FILE" up -d --force-recreate --wait; then
    show_compose_diagnostics
    dotfiles_die "Hermes Docker Compose startup failed."
  fi
  docker_command compose -f "$COMPOSE_FILE" ps
  dotfiles_wait_for "$SERVICE_WAIT_ATTEMPTS" "Hermes API port" \
    nc -z 127.0.0.1 "${HERMES_API_PORT:-8642}"
  dotfiles_wait_for "$SERVICE_WAIT_ATTEMPTS" "Hermes dashboard port" \
    nc -z 127.0.0.1 "${HERMES_DASHBOARD_PORT:-9119}"
  dotfiles_wait_for "$SERVICE_WAIT_ATTEMPTS" "Hermes browser viewer port" \
    nc -z 127.0.0.1 "${HERMES_BROWSER_VIEW_PORT:-6080}"
}

main() {
  preflight
  dotfiles_link_checkout "$ROOT"
  capture_host_identity
  apply_nixos_system
  apply_chezmoi
  start_hermes_stack
  export DOTFILES_VERIFY_SYSTEM_LAYER=nixos
  dotfiles_run_in_group docker "$VERIFY_ENVIRONMENT" --runtime
  dotfiles_log "NixOS setup complete."
}

main "$@"
