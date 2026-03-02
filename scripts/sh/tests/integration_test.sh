#!/bin/bash
set -e

echo "========================================"
echo "NixOS Integration Test"
echo "========================================"

# List of commands to check
COMMANDS=(
  "nvim"
  "wezterm"
  "zed"
  "task"
  "op"
  "gh"
  "rg"
  "fd"
  "eza"
  "fzf"
  "zoxide"
)

# Interop commands (Windows binaries exposed to WSL)
INTEROP_COMMANDS=(
  "antigravity"
)

FAILED=0

check_command() {
  local cmd=$1
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "[OK] $cmd: $(command -v "$cmd")"
  else
    echo "[失敗] $cmd: 見つかりません"
    FAILED=1
  fi
}

echo "ネイティブ/Nixpkgs ツールを確認中..."
for cmd in "${COMMANDS[@]}"; do
  check_command "$cmd"
done

echo ""
echo "Windows 相互運用ツールを確認中..."
for cmd in "${INTEROP_COMMANDS[@]}"; do
  check_command "$cmd"
done

echo ""
if [ $FAILED -eq 0 ]; then
  echo "成功: すべてのツールがインストールされています。"
  exit 0
else
  echo "失敗: 一部のツールが不足しています。"
  exit 1
fi
