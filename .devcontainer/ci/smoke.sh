#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.local/npm/bin:$PATH"

check() {
  local out
  out=$("$@" 2>&1) || {
    echo "FAIL $1 (exit $?)"
    exit 1
  }
  echo "OK  $1: ${out%%$'\n'*}"
}

echo "=== Smoke test ==="
check nvim --version
check tmux -V
check chezmoi --version
echo "=== Smoke test passed ==="
