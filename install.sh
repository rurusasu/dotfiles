#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
os="$(uname -s)"
arch="$(uname -m)"

case "$os:$arch" in
Darwin:arm64) installer=install-macos.sh ;;
Linux:x86_64 | Linux:aarch64 | Linux:arm64)
  if [[ -e /etc/NIXOS ]]; then
    installer=install-nixos.sh
  else
    installer=home-manager
  fi
  ;;
*)
  printf 'Unsupported platform: %s/%s (Windows uses install.cmd).\n' "$os" "$arch" >&2
  exit 1
  ;;
esac

load_nix() {
  local profile
  command -v nix >/dev/null 2>&1 && return 0
  for profile in \
    /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh \
    "$HOME/.nix-profile/etc/profile.d/nix.sh"; do
    if [[ -r $profile ]]; then
      # shellcheck source=/dev/null
      . "$profile"
      command -v nix >/dev/null 2>&1 && return 0
    fi
  done
  return 1
}

if ! load_nix; then
  case "$os" in
  Darwin) curl -fsSL https://install.lix.systems/lix | sh -s -- install --no-confirm ;;
  Linux) curl -fsSL https://nixos.org/nix/install | sh -s -- --no-daemon ;;
  esac
  load_nix || {
    printf 'Nix is unavailable after installation.\n' >&2
    exit 1
  }
fi

if [[ $installer == home-manager ]]; then
  case "$arch" in
  x86_64) system=x86_64-linux ;;
  aarch64 | arm64) system=aarch64-linux ;;
  esac
  nix --accept-flake-config --extra-experimental-features 'nix-command flakes' \
    flake update --flake "$ROOT"
  exec nix --accept-flake-config --extra-experimental-features 'nix-command flakes' \
    run "$ROOT#home-manager" -- switch --flake "$ROOT#$system" --impure "$@"
fi

exec "$ROOT/scripts/sh/$installer" "$@"
