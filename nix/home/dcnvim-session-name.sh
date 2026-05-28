#!/usr/bin/env bash
# _dcnvim_session_name: tmux セッション名を決定する。
# `tm` (nix/home/common.nix) と同じく、 ghq 配下なら slug basename、
# それ以外は workspace basename を返す pure function。
# 単独ファイルにして bats からテスト可能にする。
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
