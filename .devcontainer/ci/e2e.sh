#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.local/npm/bin:$PATH"

echo "=== Neovim headless E2E ==="
timeout 30 nvim --headless -i NONE \
  -c 'lua if vim.v.errmsg ~= "" then vim.cmd.cquit(1) end' -c qa || {
  nvim_status=$?
  echo "FAIL Neovim headless: exit $nvim_status"
  exit "$nvim_status"
}
echo "OK  Neovim headless"
