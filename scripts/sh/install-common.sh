#!/usr/bin/env bash

DOTFILES_LOG_PREFIX="${DOTFILES_LOG_PREFIX:-dotfiles-install}"
DOTFILES_NIX_PROFILE_SCRIPT="${DOTFILES_NIX_PROFILE_SCRIPT:-/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh}"
DOTFILES_WAIT_SLEEP_SECONDS="${DOTFILES_WAIT_SLEEP_SECONDS:-2}"

dotfiles_log() {
  printf '\033[1;34m[%s]\033[0m %s\n' "$DOTFILES_LOG_PREFIX" "$*"
}

dotfiles_die() {
  printf '\033[1;31m[%s]\033[0m %s\n' "$DOTFILES_LOG_PREFIX" "$*" >&2
  exit 1
}

dotfiles_have() {
  command -v "$1" >/dev/null 2>&1
}

dotfiles_wait_for() {
  local attempts="$1"
  local label="$2"
  shift 2

  local attempt
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if "$@" >/dev/null 2>&1; then
      return 0
    fi
    if ((attempt < attempts)); then
      sleep "$DOTFILES_WAIT_SLEEP_SECONDS"
    fi
  done

  dotfiles_die "Timed out waiting for $label after $attempts attempts."
}

dotfiles_load_nix() {
  if [[ -r $DOTFILES_NIX_PROFILE_SCRIPT ]]; then
    # shellcheck source=/dev/null
    . "$DOTFILES_NIX_PROFILE_SCRIPT"
  fi
}

dotfiles_canonical_directory() {
  (
    cd "$1" || exit 1
    pwd -P
  )
}

dotfiles_link_checkout() {
  local root="$1"
  local target="${DOTFILES_CHECKOUT_TARGET:-$HOME/.dotfiles}"

  if [[ -d $target ]] &&
    [[ "$(dotfiles_canonical_directory "$target")" == "$(dotfiles_canonical_directory "$root")" ]]; then
    return
  fi

  if [[ -e $target || -L $target ]]; then
    local backup
    backup="$target.backup.$(date +%Y%m%d%H%M%S)"
    mv "$target" "$backup"
    dotfiles_log "Moved existing $target to $backup"
  fi

  ln -s "$root" "$target"
}

dotfiles_run_in_group() {
  local group="$1"
  shift

  if [[ " $(id -Gn) " == *" $group "* ]]; then
    "$@"
    return
  fi

  local user="${DOTFILES_USER:-${USER:-}}"
  [[ -n $user ]] || dotfiles_die "Unable to determine the user for group $group."
  [[ " $(id -Gn "$user") " == *" $group "* ]] ||
    dotfiles_die "User $user is not a member of group $group after activation."
  dotfiles_have sg || dotfiles_die "sg is required to enter the newly activated $group group."

  local command_string
  printf -v command_string '%q ' "$@"
  sg "$group" -c "$command_string"
}
