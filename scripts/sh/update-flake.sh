#!/usr/bin/env bash

dotfiles_update_flake() {
  local root="$1"

  dotfiles_have nix || dotfiles_die "Nix is required to update flake inputs."
  dotfiles_log "Updating Nix flake inputs..."
  if (
    cd "$root" || dotfiles_die "Unable to enter dotfiles checkout: $root"
    nix flake update
  ); then
    return 0
  else
    local status=$?
    dotfiles_log "Nix flake input update failed."
    exit "$status"
  fi
}
