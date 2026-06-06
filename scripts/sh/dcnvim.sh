#!/usr/bin/env bash
# Shared dcnvim implementation for POSIX shells.
# Source this file from bash/zsh profiles; do not execute it directly.

_dcnvim_abs_path() {
  local path="$1"
  if [ -d "$path" ]; then
    (cd "$path" 2>/dev/null && pwd -P)
    return
  fi

  realpath -e "$path" 2>/dev/null || readlink -f "$path"
}

# _dcnvim_session_name: tmux セッション名を決定する。
# `tm` と同じく、ghq 配下なら slug basename、それ以外は workspace
# basename を返す pure function。
#
# Usage: _dcnvim_session_name <workspace-abs-path> <ghq-root-or-empty>
_dcnvim_session_name() {
  local workspace="$1"
  local ghq_root="${2%/}"
  if [ -n "$ghq_root" ] && [ "${workspace#"$ghq_root"/}" != "$workspace" ]; then
    local slug="${workspace#"$ghq_root"/}"
    slug="${slug%/}"
    printf '%s\n' "${slug##*/}"
  else
    basename "${workspace%/}"
  fi
}

_dcnvim_shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# devcontainer: enter the project's devcontainer in a tmux session and start
# nvim inside it. Terminal-agnostic (works in WezTerm, Windows Terminal, Warp,
# etc.). Re-running attaches to the existing tmux session so nvim state
# survives terminal close.
#
# Usage: dcnvim [workspace-folder]
#   No arg + cwd has .devcontainer  -> use cwd
#   No arg + no .devcontainer       -> ghq list | fzf picker
#   Explicit path                   -> use that path
#
# Requires: @devcontainers/cli on host; bootstrap.sh ran inside the container
# to provide nvim + tmux. See bootstrap.sh at repo root.
dcnvim() {
  local workspace
  if [ -n "${1:-}" ]; then
    workspace="$(_dcnvim_abs_path "$1")" || return 1
  elif [ -d "$PWD/.devcontainer" ] || [ -f "$PWD/.devcontainer.json" ]; then
    workspace="$(_dcnvim_abs_path "$PWD")" || return 1
  elif command -v ghq >/dev/null 2>&1 && command -v fzf >/dev/null 2>&1; then
    local ghq_root selected
    ghq_root="$(ghq root 2>/dev/null)" || ghq_root=""
    selected="$(ghq list | fzf --prompt='devcontainer> ')" || return 0
    workspace="$(_dcnvim_abs_path "$ghq_root/$selected")" || return 1
  else
    workspace="$(_dcnvim_abs_path "$PWD")" || return 1
  fi

  if ! command -v devcontainer >/dev/null 2>&1; then
    echo "dcnvim: devcontainer CLI not found. Install with: npm i -g @devcontainers/cli" >&2
    return 127
  fi
  if [ ! -d "$workspace/.devcontainer" ] && [ ! -f "$workspace/.devcontainer.json" ]; then
    echo "dcnvim: no .devcontainer/ or .devcontainer.json under $workspace" >&2
    return 1
  fi

  # Bring container up + inject dotfiles. CLI does not read
  # ~/.config/devcontainer/devcontainer.json (that's a VS Code extension
  # config), so dotfiles flags must be passed explicitly. Idempotent: skips
  # on a container already up.
  local dotfiles_url="${DOTFILES_REPOSITORY_URL:-https://github.com/rurusasu/dotfiles}"
  devcontainer up \
    --workspace-folder "$workspace" \
    --dotfiles-repository "$dotfiles_url" \
    --dotfiles-install-command bootstrap.sh \
    >/dev/null || {
    echo "dcnvim: devcontainer up failed" >&2
    return 1
  }

  local ghq_root=""
  command -v ghq >/dev/null 2>&1 && ghq_root="$(ghq root 2>/dev/null || true)"

  local session_name session_name_quoted
  session_name="$(_dcnvim_session_name "$workspace" "$ghq_root")"
  session_name_quoted="$(_dcnvim_shell_quote "$session_name")"

  # bash -l reads ~/.profile (not ~/.bashrc); export PATH inline so the
  # container's just-bootstrapped ~/.local/bin/nvim is found. nvim/tmux
  # presence is checked because tmux exits 0 if its child command is missing,
  # masking the failure to the host.
  devcontainer exec --workspace-folder "$workspace" -- \
    bash -lc "
      export PATH=\"\$HOME/.local/bin:\$PATH\"
      command -v nvim >/dev/null 2>&1 || {
        echo 'dcnvim: nvim not installed in container — run ~/.dotfiles/bootstrap.sh first' >&2
        exit 127
      }
      command -v tmux >/dev/null 2>&1 || {
        echo 'dcnvim: tmux not installed in container — run ~/.dotfiles/bootstrap.sh first' >&2
        exit 127
      }
      tmux new -A -s $session_name_quoted 'nvim .'
    "
}
