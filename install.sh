#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
os="$(uname -s)"
arch="$(uname -m)"

if [[ $os == "Darwin" && $arch == "arm64" ]]; then
  exec "$ROOT/scripts/sh/install-macos.sh" "$@"
fi

if [[ $os == MINGW* || $os == MSYS* || $os == CYGWIN* ]]; then
  printf 'Windows setup uses install.cmd.\n' >&2
  exit 1
fi

if [[ $os == "Darwin" ]]; then
  printf 'This installer supports Apple Silicon Macs only (detected %s).\n' "$arch" >&2
  exit 1
fi

printf 'This installer supports Apple Silicon macOS only. Use the existing NixOS/Linux instructions on %s.\n' "$os" >&2
exit 1
