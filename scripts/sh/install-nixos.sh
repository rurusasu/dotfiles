#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# shellcheck source=scripts/sh/lib/install-options.sh
. "$ROOT/scripts/sh/lib/install-options.sh"
host=linux
if [[ $(uname -r) == *[Mm]icrosoft* ]]; then
  host=wsl
fi
flake_ref=${DOTFILES_FLAKE_REF:-$ROOT#$host}
if [[ $host == wsl ]]; then
  account_flake=${DOTFILES_FLAKE_REF:-path:$ROOT#$host}
  configured_user=$(nix --accept-flake-config --extra-experimental-features 'nix-command flakes' \
    eval --raw "${account_flake%#*}#nixosConfigurations.${account_flake##*#}.config.wsl.defaultUser" --impure --no-update-lock-file)
  current_user=$(id -un)
  if [[ $configured_user != "$current_user" ]]; then
    printf 'WSL user %s differs from declared wsl.defaultUser %s. Use nixos-rebuild boot and the official WSL restart procedure before switch: https://nix-community.github.io/NixOS-WSL/how-to/change-username.html\n' \
      "$current_user" "$configured_user" >&2
    exit 1
  fi
fi
exec sudo ${install_sudo_options[@]+"${install_sudo_options[@]}"} nixos-rebuild switch --flake "$flake_ref" --impure \
  --option accept-flake-config true --option experimental-features 'nix-command flakes' \
  ${install_flake_options[@]+"${install_flake_options[@]}"} "$@"
