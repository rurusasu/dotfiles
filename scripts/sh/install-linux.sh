#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
export DOTFILES_LOG_PREFIX="linux-install"
# shellcheck source=/dev/null
. "$ROOT/scripts/sh/install-common.sh"
# shellcheck source=/dev/null
. "$ROOT/scripts/sh/hermes-agent.sh"

COMPOSE_FILE="${DOTFILES_COMPOSE_FILE:-$ROOT/docker/hermes-agent/compose.yml}"
OS_RELEASE_FILE="${DOTFILES_OS_RELEASE_FILE:-/etc/os-release}"
SYSTEMD_DIR="${DOTFILES_SYSTEMD_DIR:-/run/systemd/system}"
SERVICE_WAIT_ATTEMPTS="${DOTFILES_SERVICE_WAIT_ATTEMPTS:-60}"
SYSTEMD_WAIT_ATTEMPTS="${DOTFILES_SYSTEMD_WAIT_ATTEMPTS:-30}"
VERIFY_ENVIRONMENT="${DOTFILES_VERIFY_ENVIRONMENT:-$ROOT/scripts/sh/verify-environment.sh}"
LINUX_CONFIG=""

preflight() {
  [[ $(uname -s) == "Linux" ]] || dotfiles_die "Linux is required."
  [[ -r $OS_RELEASE_FILE ]] || dotfiles_die "Linux release metadata is missing: $OS_RELEASE_FILE"

  # shellcheck source=/dev/null
  . "$OS_RELEASE_FILE"
  case "${ID:-}" in
  ubuntu | debian) LINUX_CONFIG="$ID" ;;
  *) dotfiles_die "Full Linux setup supports Ubuntu and Debian only (detected ${ID:-unknown})." ;;
  esac

  local required
  for required in \
    "$ROOT/flake.nix" \
    "$ROOT/chezmoi" \
    "$COMPOSE_FILE" \
    "$VERIFY_ENVIRONMENT"; do
    [[ -e $required ]] || dotfiles_die "Required repository path is missing: $required"
  done
}

ensure_systemd() {
  [[ -d $SYSTEMD_DIR ]] || dotfiles_die "A running systemd system instance is required."
  dotfiles_have systemctl || dotfiles_die "systemctl is required."

  local attempt state=""
  for ((attempt = 1; attempt <= SYSTEMD_WAIT_ATTEMPTS; attempt++)); do
    state="$(systemctl is-system-running 2>/dev/null || true)"
    case "$state" in
    running | degraded) return ;;
    starting)
      # Hosted runners can remain globally "starting" while the manager is
      # already available for the System Manager activation below.
      [[ -n $(systemctl show --property=Version --value 2>/dev/null || true) ]] && return
      ;;
    esac
    if ((attempt < SYSTEMD_WAIT_ATTEMPTS)); then
      sleep "$DOTFILES_WAIT_SLEEP_SECONDS"
    fi
  done

  dotfiles_die "systemd is not ready after $SYSTEMD_WAIT_ATTEMPTS attempts (state: ${state:-unknown})."
}

ensure_nix() {
  dotfiles_load_nix
  if ! dotfiles_have nix; then
    dotfiles_log "Installing Nix in multi-user daemon mode..."
    curl -fsSL https://nixos.org/nix/install | sh -s -- --daemon
    dotfiles_load_nix
  fi

  dotfiles_have nix || dotfiles_die "Nix installation completed but nix is unavailable."
  mkdir -p "$HOME/.config/nix"
  local feature_line="extra-experimental-features = nix-command flakes"
  touch "$HOME/.config/nix/nix.conf"
  grep -Fxq "$feature_line" "$HOME/.config/nix/nix.conf" ||
    printf '%s\n' "$feature_line" >>"$HOME/.config/nix/nix.conf"
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
  *) dotfiles_die "Unsupported Linux Nix system: $DOTFILES_SYSTEM" ;;
  esac
}

apply_linux_system() {
  dotfiles_log "Applying System Manager and Home Manager for $LINUX_CONFIG..."
  (
    cd "$ROOT"
    nix run .#system-manager -- \
      --nix-option pure-eval false \
      switch --flake ".#$LINUX_CONFIG" --sudo
  )

  export PATH="/run/system-manager/sw/bin:/etc/profiles/per-user/$DOTFILES_USER/bin:$HOME/.nix-profile/bin:$HOME/.local/state/nix/profile/bin:$PATH"
  hash -r
}

apply_chezmoi() {
  dotfiles_have chezmoi || dotfiles_die "chezmoi is unavailable after System Manager activation."
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
  ensure_systemd
  ensure_nix
  dotfiles_link_checkout "$ROOT"
  capture_host_identity
  apply_linux_system
  apply_chezmoi
  start_hermes_stack
  dotfiles_run_in_group docker "$VERIFY_ENVIRONMENT" --runtime
  dotfiles_log "Linux setup complete."
}

main "$@"
