#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
os="$(uname -s)"
arch="$(uname -m)"

case "$os" in
Darwin)
  if [[ $arch == "arm64" ]]; then
    exec "$ROOT/scripts/sh/install-macos.sh" "$@"
  fi
  printf 'This installer supports Apple Silicon Macs only (detected %s).\n' "$arch" >&2
  exit 1
  ;;
Linux)
  if [[ -e ${DOTFILES_NIXOS_MARKER:-/etc/NIXOS} ]]; then
    exec "$ROOT/scripts/sh/install-nixos.sh" "$@"
  fi

  exec "$ROOT/scripts/sh/install-home-manager.sh" "$@"
  ;;
MINGW* | MSYS* | CYGWIN*)
  printf 'Windows setup uses install.cmd.\n' >&2
  exit 1
  ;;
*)
  printf 'Unsupported operating system: %s.\n' "$os" >&2
  exit 1
  ;;
esac
