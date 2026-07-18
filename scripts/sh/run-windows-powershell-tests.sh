#!/usr/bin/env bash
set -euo pipefail

case "$(uname -s)" in
MINGW* | MSYS* | CYGWIN*) exec pwsh.exe "$@" ;;
*) exit 0 ;;
esac
