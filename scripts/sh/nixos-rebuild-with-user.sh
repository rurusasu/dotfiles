#!/usr/bin/env bash
set -euo pipefail

# nixos-rebuild evaluates the flake as root. Pass the invoking user's identity
# through sudo so Home Manager keeps targeting the same account on every
# rebuild, not only during the initial WSL postinstall.
user="${DOTFILES_USER:-${SUDO_USER:-${USER:-}}}"
[[ -n $user ]] || {
  echo "Unable to determine the NixOS user." >&2
  exit 1
}

home="${DOTFILES_HOME:-}"
if [[ -z $home ]]; then
  if command -v getent >/dev/null 2>&1; then
    home="$(getent passwd "$user" | cut -d: -f6)"
  else
    home="/home/$user"
  fi
fi
[[ $home == /* ]] || {
  echo "Unable to determine an absolute home directory for $user." >&2
  exit 1
}

uid="${DOTFILES_UID:-$(id -u "$user")}"
gid="${DOTFILES_GID:-$(id -g "$user")}"
group="${DOTFILES_GROUP:-$(id -gn "$user")}"

exec sudo /usr/bin/env \
  "DOTFILES_USER=$user" \
  "DOTFILES_HOME=$home" \
  "DOTFILES_UID=$uid" \
  "DOTFILES_GID=$gid" \
  "DOTFILES_GROUP=$group" \
  nixos-rebuild "$@"
