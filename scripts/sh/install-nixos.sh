#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
host=linux
if [[ $(uname -r) == *[Mm]icrosoft* ]]; then
  host=nixos
fi
nix --accept-flake-config --extra-experimental-features 'nix-command flakes' \
  flake update --flake "$ROOT"
exec sudo nixos-rebuild switch --flake "$ROOT#$host" --impure \
  --option accept-flake-config true --option experimental-features 'nix-command flakes' "$@"
