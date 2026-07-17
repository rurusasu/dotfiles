#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
export DOTFILES_LOG_PREFIX="home-manager-install"
# shellcheck source=/dev/null
. "$ROOT/scripts/sh/install-common.sh"

ensure_opt_in() {
  [[ ${DOTFILES_ALLOW_USER_ONLY:-0} == "1" ]] ||
    dotfiles_die "Set DOTFILES_ALLOW_USER_ONLY=1 to accept setup without Docker/systemd management."
}

ensure_nix() {
  dotfiles_load_nix
  if ! dotfiles_have nix; then
    dotfiles_log "Installing Nix in single-user mode..."
    curl -fsSL https://nixos.org/nix/install | sh -s -- --no-daemon
    dotfiles_load_nix
    if [[ -r $HOME/.nix-profile/etc/profile.d/nix.sh ]]; then
      # shellcheck source=/dev/null
      . "$HOME/.nix-profile/etc/profile.d/nix.sh"
    fi
  fi

  dotfiles_have nix || dotfiles_die "Nix installation completed but nix is unavailable."
  mkdir -p "$HOME/.config/nix"
  local feature_line="extra-experimental-features = nix-command flakes"
  touch "$HOME/.config/nix/nix.conf"
  grep -Fxq "$feature_line" "$HOME/.config/nix/nix.conf" ||
    printf '%s\n' "$feature_line" >>"$HOME/.config/nix/nix.conf"
}

capture_user_identity() {
  export DOTFILES_USER="${SUDO_USER:-${USER:-}}"
  export DOTFILES_HOME="$HOME"
  [[ -n $DOTFILES_USER && $DOTFILES_HOME == /* ]] ||
    dotfiles_die "A current user and absolute home directory are required."

  export DOTFILES_SYSTEM
  DOTFILES_SYSTEM="$(nix eval --impure --raw --expr builtins.currentSystem)"
  case "$DOTFILES_SYSTEM" in
  x86_64-linux | aarch64-linux) ;;
  *) dotfiles_die "Unsupported Linux Nix system: $DOTFILES_SYSTEM" ;;
  esac
}

activate_home_manager() {
  local activation
  activation="$({
    cd "$ROOT"
    nix build --impure --no-link --print-out-paths \
      ".#homeConfigurations.\"$DOTFILES_SYSTEM\".activationPackage"
  })"
  [[ -n $activation && $activation != *$'\n'* && -x $activation/activate ]] ||
    dotfiles_die "Home Manager activation package was not produced."
  "$activation/activate"
  export PATH="$HOME/.nix-profile/bin:$HOME/.local/state/nix/profile/bin:$PATH"
  hash -r
}

apply_chezmoi() {
  dotfiles_have chezmoi || dotfiles_die "chezmoi is unavailable after Home Manager activation."
  chezmoi init --source "$ROOT/chezmoi"
  chezmoi apply --force
}

main() {
  ensure_opt_in
  [[ $(uname -s) == "Linux" ]] || dotfiles_die "Linux is required."
  ensure_nix
  dotfiles_link_checkout "$ROOT"
  capture_user_identity
  activate_home_manager
  apply_chezmoi
  printf 'User-only setup complete; Docker/systemd were not configured.\n'
}

main "$@"
