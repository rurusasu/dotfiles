#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# Resolve macOS consent before updating inputs or building the configuration.
sudo --set-home /bin/bash "$ROOT/scripts/sh/ensure-macos-permissions.sh" "$HOME" "$(command -v touch)"
nix --accept-flake-config --extra-experimental-features 'nix-command flakes' \
  flake update --flake "$ROOT"
exec sudo --set-home "$(command -v nix)" --accept-flake-config \
  --extra-experimental-features 'nix-command flakes' \
  run "$ROOT#darwin-rebuild" -- switch --flake "$ROOT#macos" --impure \
  --option accept-flake-config true "$@"
