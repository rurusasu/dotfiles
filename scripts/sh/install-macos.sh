#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
nix --accept-flake-config --extra-experimental-features 'nix-command flakes' \
  flake update --flake "$ROOT"
exec sudo "$(command -v nix)" --accept-flake-config \
  --extra-experimental-features 'nix-command flakes' \
  run "$ROOT#darwin-rebuild" -- switch --flake "$ROOT#macos" --impure "$@"
