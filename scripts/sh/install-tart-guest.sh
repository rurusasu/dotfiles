#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

load_nix() {
  if [[ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
    # shellcheck source=/dev/null
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  elif [[ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]]; then
    # shellcheck source=/dev/null
    . "$HOME/.nix-profile/etc/profile.d/nix.sh"
  fi
}

ensure_nix() {
  load_nix
  if command -v nix >/dev/null 2>&1; then
    return
  fi
  command -v curl >/dev/null 2>&1 || {
    printf 'tart-guest: curl is required to install Nix.\n' >&2
    exit 1
  }
  curl -fsSL https://nixos.org/nix/install | sh -s -- --daemon --yes
  load_nix
  command -v nix >/dev/null 2>&1 || {
    printf 'tart-guest: Nix installation completed but nix is unavailable.\n' >&2
    exit 1
  }
}

install_cli_profile() {
  local state_dir="$HOME/.local/state/dotfiles"
  local profile_link="$state_dir/tart-profile"
  local temporary_link="$state_dir/tart-profile.next.$$"
  local command target

  mkdir -p "$state_dir" "$HOME/.local/bin"
  [[ ! -e $profile_link || -L $profile_link ]] || {
    printf 'tart-guest: managed profile path is not a symlink: %s\n' "$profile_link" >&2
    exit 1
  }
  trap 'rm -f -- "$temporary_link"' RETURN
  nix build "$REPO_ROOT#tart-minimal" --out-link "$temporary_link"
  mv -f -- "$temporary_link" "$profile_link"
  trap - RETURN

  for command in git chezmoi nvim codex; do
    target="$HOME/.local/bin/$command"
    [[ ! -e $target || -L $target ]] || {
      printf 'tart-guest: refusing to replace unmanaged command: %s\n' "$target" >&2
      exit 1
    }
    ln -sfn "$profile_link/bin/$command" "$target"
  done
}

install_wezterm() {
  command -v brew >/dev/null 2>&1 || {
    printf 'tart-guest: Homebrew is required for WezTerm.\n' >&2
    exit 1
  }
  if ! brew list --cask --versions wezterm@nightly >/dev/null 2>&1; then
    brew install --cask wezterm@nightly
  fi
}

apply_dotfiles() {
  export PATH="$HOME/.local/bin:$PATH"
  chezmoi init --source "$REPO_ROOT/chezmoi"
  chezmoi apply --force
}

ensure_nix
install_cli_profile
install_wezterm
apply_dotfiles
