#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
export DOTFILES_LOG_PREFIX="macos-install"
# shellcheck source=/dev/null
. "$ROOT/scripts/sh/install-common.sh"

COMPOSE_FILE="$ROOT/docker/hermes-agent/compose.yml"
DOCKER_APP="${DOTFILES_DOCKER_APP_PATH:-/Applications/Docker.app}"
DOCKER_SETUP_MARKER="${DOTFILES_DOCKER_SETUP_MARKER:-$HOME/.config/dotfiles/docker-desktop-installed}"
DOCKER_WAIT_ATTEMPTS="${DOTFILES_DOCKER_WAIT_ATTEMPTS:-120}"
SERVICE_WAIT_ATTEMPTS="${DOTFILES_SERVICE_WAIT_ATTEMPTS:-60}"
VERIFY_ENVIRONMENT="${DOTFILES_VERIFY_ENVIRONMENT:-$ROOT/scripts/sh/verify-environment.sh}"
BASHRC_PATH="${DOTFILES_BASHRC_PATH:-/etc/bashrc}"
ZSHRC_PATH="${DOTFILES_ZSHRC_PATH:-/etc/zshrc}"
USER_PROFILE_ROOT="${DOTFILES_USER_PROFILE_ROOT:-/etc/profiles/per-user}"

preflight() {
  local os arch version major required
  os="$(uname -s)"
  arch="$(uname -m)"
  [[ $os == "Darwin" ]] || dotfiles_die "macOS is required (detected $os)."
  [[ $arch == "arm64" ]] || dotfiles_die "Apple Silicon is required (detected $arch)."

  version="$(sw_vers -productVersion)"
  major="${version%%.*}"
  [[ $major =~ ^[0-9]+$ ]] || dotfiles_die "Unable to parse macOS version: $version"
  ((major >= 26)) || dotfiles_die "macOS 26 or later is required (detected $version)."

  for required in \
    "$ROOT/flake.nix" \
    "$ROOT/chezmoi" \
    "$COMPOSE_FILE" \
    "$VERIFY_ENVIRONMENT"; do
    [[ -e $required ]] || dotfiles_die "Required repository path is missing: $required"
  done
}

ensure_command_line_tools() {
  if xcode-select -p >/dev/null 2>&1; then
    return
  fi

  xcode-select --install || true
  dotfiles_die "Command Line Tools installation was requested. Complete it, then rerun ./install.sh."
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

preserve_shell_rc_for_nix_darwin() {
  local rc backup
  for rc in "$BASHRC_PATH" "$ZSHRC_PATH"; do
    [[ -e $rc || -L $rc ]] || continue
    [[ -L $rc ]] && continue

    backup="$rc.before-nix-darwin"
    [[ ! -e $backup && ! -L $backup ]] ||
      dotfiles_die "Refusing to overwrite existing nix-darwin backup: $backup"

    dotfiles_log "Preserving existing $rc as $backup..."
    sudo mv "$rc" "$backup"
  done
}

stop_existing_docker_desktop() {
  local docker_cli="$DOCKER_APP/Contents/Resources/bin/docker"
  [[ -x $docker_cli ]] || return 0
  "$docker_cli" info >/dev/null 2>&1 || return 0

  dotfiles_log "Stopping Docker Desktop before declarative cask activation..."
  "$docker_cli" desktop stop --timeout 120
}

apply_darwin_system() {
  export DOTFILES_USER="${SUDO_USER:-$USER}"
  export DOTFILES_HOME="$HOME"
  export DOTFILES_ROOT="$ROOT"
  local nix_bin
  nix_bin="$(command -v nix)"

  dotfiles_log "Applying nix-darwin, nix-homebrew, and Home Manager..."
  (
    cd "$ROOT"
    sudo /usr/bin/env \
      "NIX_CONFIG=extra-experimental-features = nix-command flakes" \
      "DOTFILES_USER=$DOTFILES_USER" \
      "DOTFILES_HOME=$DOTFILES_HOME" \
      "DOTFILES_ROOT=$DOTFILES_ROOT" \
      "$nix_bin" run .#darwin-rebuild -- switch --flake .#macos --impure
  )

  export PATH="/run/current-system/sw/bin:$USER_PROFILE_ROOT/$DOTFILES_USER/bin:$HOME/.nix-profile/bin:$HOME/.local/state/nix/profile/bin:/opt/homebrew/bin:/opt/homebrew/sbin:$DOCKER_APP/Contents/Resources/bin:$PATH"
  hash -r
}

setup_docker_runtime() {
  [[ -d $DOCKER_APP ]] ||
    dotfiles_die "Docker Desktop was not installed by nix-darwin: $DOCKER_APP"

  local installer="$DOCKER_APP/Contents/MacOS/install"
  [[ -x $installer ]] || dotfiles_die "Docker Desktop installer not found: $installer"

  if [[ ! -f $DOCKER_SETUP_MARKER ]]; then
    dotfiles_log "Accepting the Docker Desktop license for personal use..."
    sudo "$installer" --accept-license --user="${SUDO_USER:-$USER}"
    mkdir -p "$(dirname "$DOCKER_SETUP_MARKER")"
    touch "$DOCKER_SETUP_MARKER"
  fi

  dotfiles_have docker || dotfiles_die "Docker CLI is unavailable after nix-darwin activation."
  if ! docker info >/dev/null 2>&1; then
    docker desktop start --timeout 120
    dotfiles_wait_for "$DOCKER_WAIT_ATTEMPTS" "Docker Desktop engine" docker info
  fi
  docker compose version >/dev/null
}

apply_chezmoi() {
  dotfiles_have chezmoi || dotfiles_die "chezmoi is unavailable after nix-darwin activation."
  chezmoi init --source "$ROOT/chezmoi"
  chezmoi apply --force
}

show_compose_diagnostics() {
  docker compose -f "$COMPOSE_FILE" ps || true
  docker compose -f "$COMPOSE_FILE" logs --tail=100 || true
}

start_hermes_stack() {
  dotfiles_log "Validating Hermes Docker Compose configuration..."
  docker compose -f "$COMPOSE_FILE" config
  dotfiles_log "Building Hermes images..."
  docker compose -f "$COMPOSE_FILE" build --pull
  dotfiles_log "Starting Hermes services..."
  if ! docker compose -f "$COMPOSE_FILE" up -d --force-recreate --wait; then
    show_compose_diagnostics
    dotfiles_die "Hermes Docker Compose startup failed."
  fi
  docker compose -f "$COMPOSE_FILE" ps
  dotfiles_wait_for "$SERVICE_WAIT_ATTEMPTS" "Hermes API port" \
    nc -z 127.0.0.1 "${HERMES_API_PORT:-8642}"
  dotfiles_wait_for "$SERVICE_WAIT_ATTEMPTS" "Hermes dashboard port" \
    nc -z 127.0.0.1 "${HERMES_DASHBOARD_PORT:-9119}"
  dotfiles_wait_for "$SERVICE_WAIT_ATTEMPTS" "Hermes browser viewer port" \
    nc -z 127.0.0.1 "${HERMES_BROWSER_VIEW_PORT:-6080}"
}

main() {
  preflight
  ensure_command_line_tools
  ensure_nix
  dotfiles_link_checkout "$ROOT"
  preserve_shell_rc_for_nix_darwin
  stop_existing_docker_desktop
  apply_darwin_system
  setup_docker_runtime
  apply_chezmoi
  start_hermes_stack
  "$VERIFY_ENVIRONMENT" --runtime
  dotfiles_log "macOS setup complete."
}

main "$@"
