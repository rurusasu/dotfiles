#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.local/npm/bin:$PATH"

echo "=== tmux + nvim headless E2E ==="
ci_tmp=$(mktemp -d)
ci_socket="dotfiles-nvim-ci-$$"
cleanup() {
  tmux -L "$ci_socket" kill-server 2>/dev/null || true
}
trap cleanup EXIT
# Capture the child status; successful tmux startup alone does not prove nvim ran.
tmux -L "$ci_socket" new-session -d -s ci \
  "nvim --headless -i NONE -c 'lua if vim.v.errmsg ~= \"\" then vim.cmd.cquit(1) end' -c qa; printf '%s\\n' \$? > '$ci_tmp/status'"
for ((attempt = 0; attempt < 300; attempt++)); do
  [[ -f "$ci_tmp/status" ]] && break
  sleep 0.1
done
if [[ ! -f "$ci_tmp/status" ]]; then
  echo "FAIL tmux + nvim: timed out"
  exit 1
fi
read -r nvim_status <"$ci_tmp/status"
if [[ $nvim_status != 0 ]]; then
  echo "FAIL tmux + nvim: exit $nvim_status"
  exit 1
fi
echo "OK  tmux + nvim headless"
