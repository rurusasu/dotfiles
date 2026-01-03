#!/bin/bash

# Dotfiles インストールスクリプト
# NixOS の設定をビルドし、Windows 側にターミナル設定を適用します

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# 色付き出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info() { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo "=== Dotfiles インストール ==="
echo ""

# NixOS かどうかを確認
if [ ! -f /etc/NIXOS ]; then
    error "NixOS が検出されませんでした。"
    echo ""
    echo "このスクリプトは NixOS 環境で実行してください。"
    echo ""
    if grep -qi microsoft /proc/version 2>/dev/null; then
        echo "WSL で NixOS をセットアップするには、Windows PowerShell (管理者) から:"
        echo "  .\\scripts\\powershell\\install-nixos-wsl.ps1"
    fi
    exit 1
fi

# ~/.dotfiles の確認
if [ ! -d ~/.dotfiles ]; then
    warn "~/.dotfiles が見つかりません。シンボリックリンクを作成します..."
    ln -sf "${DOTFILES_DIR}" ~/.dotfiles
    success "~/.dotfiles -> ${DOTFILES_DIR}"
fi

# NixOS rebuild
info "NixOS 設定をビルドしています..."
echo ""

if sudo nixos-rebuild switch --flake ~/.dotfiles#nixos --impure; then
    success "NixOS 設定が適用されました"
else
    error "NixOS rebuild に失敗しました"
    exit 1
fi

echo ""

# WSL かどうかを確認して、Windows 設定を適用
if grep -qi microsoft /proc/version 2>/dev/null; then
    echo ""
    info "WSL 環境が検出されました。Windows 側の設定を適用しますか？"
    echo ""
    echo "適用される設定:"
    echo "  - Windows Terminal settings.json"
    echo "  - WezTerm wezterm.lua"
    echo "  - Winget パッケージ (オプション)"
    echo ""
    read -p "続行しますか? (y/N): " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        info "Windows 設定を適用しています..."
        echo ""

        # PowerShell スクリプトのパスを取得
        WINDOWS_DOTFILES=$(wslpath -w "${DOTFILES_DIR}")
        APPLY_SCRIPT="${WINDOWS_DOTFILES}\\scripts\\powershell\\update-windows-settings.ps1"

        # 管理者権限が必要なことを通知
        warn "Windows Terminal への適用には管理者権限が必要です。"
        warn "UAC プロンプトが表示される場合があります。"
        echo ""

        # PowerShell を管理者として実行
        if powershell.exe -NoProfile -Command "Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"${APPLY_SCRIPT}\" -SkipWinget' -Verb RunAs -Wait" 2>/dev/null; then
            success "Windows 設定が適用されました"
        else
            warn "Windows 設定の適用に失敗しました。"
            echo ""
            echo "手動で適用するには、Windows PowerShell (管理者) から:"
            echo "  .\\scripts\\powershell\\update-windows-settings.ps1"
        fi
    else
        info "Windows 設定の適用をスキップしました"
        echo ""
        echo "後で適用するには、Windows PowerShell (管理者) から:"
        echo "  .\\scripts\\powershell\\update-windows-settings.ps1"
    fi
fi

echo ""
echo "=== インストール完了 ==="
echo ""
success "Dotfiles が正常にインストールされました"
echo ""
echo "次回以降の更新は:"
echo "  nrs  # または: sudo nixos-rebuild switch --flake ~/.dotfiles#nixos --impure"
echo ""
