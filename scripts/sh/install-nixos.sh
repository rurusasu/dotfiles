#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
host=linux
if [[ $(uname -r) == *[Mm]icrosoft* ]]; then
  host=nixos
  configured_user=$(nix --accept-flake-config --extra-experimental-features 'nix-command flakes' \
    eval --raw "path:$ROOT#nixosConfigurations.nixos.config.wsl.defaultUser" --impure --no-write-lock-file)
  current_user=$(id -un)
  if [[ $configured_user != "$current_user" ]]; then
    printf 'WSL user %s differs from declared wsl.defaultUser %s. Use nixos-rebuild boot and the official WSL restart procedure before switch: https://nix-community.github.io/NixOS-WSL/how-to/change-username.html\n' \
      "$current_user" "$configured_user" >&2
    exit 1
  fi
fi
nix --accept-flake-config --extra-experimental-features 'nix-command flakes' \
  flake update --flake "$ROOT"
exec sudo nixos-rebuild switch --flake "$ROOT#$host" --impure \
  --option accept-flake-config true --option experimental-features 'nix-command flakes' "$@"
