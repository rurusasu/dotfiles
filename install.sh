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

  os_release_file="${DOTFILES_OS_RELEASE_FILE:-/etc/os-release}"
  if [[ ! -r $os_release_file ]]; then
    printf 'Linux distribution metadata is unavailable: %s\n' "$os_release_file" >&2
    exit 1
  fi
  ID=""
  # shellcheck source=/dev/null
  . "$os_release_file"

  case "${ID:-}" in
  ubuntu | debian)
    exec "$ROOT/scripts/sh/install-linux.sh" "$@"
    ;;
  *)
    if [[ ${DOTFILES_ALLOW_USER_ONLY:-0} != "1" ]]; then
      printf 'Unsupported Linux distribution (%s). Set DOTFILES_ALLOW_USER_ONLY=1 for Home Manager only.\n' "${ID:-unknown}" >&2
      exit 1
    fi
    exec "$ROOT/scripts/sh/install-home-manager.sh" "$@"
    ;;
  esac
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
