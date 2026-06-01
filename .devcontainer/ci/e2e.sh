#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.local/npm/bin:$PATH"

echo "=== tmux + nvim headless E2E ==="
tmux new-session -d -s ci "nvim --headless +qa"
sleep 2
tmux kill-session -t ci 2>/dev/null || true
echo "OK  tmux + nvim headless"
