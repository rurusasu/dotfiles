#!/bin/bash

# Dotfiles インストールスクリプト
# GNU Stow を使って設定ファイルのシンボリックリンクを作成

set -e

# スクリプトのディレクトリに移動
cd "$(dirname "$0")"

echo "=== Dotfiles インストール ==="
echo ""

# GNU Stow がインストールされているか確認
if ! command -v stow &> /dev/null; then
    echo "エラー: GNU Stow がインストールされていません"
    echo "以下のコマンドでインストールしてください："
    echo "  sudo apt install stow"
    exit 1
fi

# 利用可能なパッケージを取得
PACKAGES=(bash git vim claude vscode nvim)

echo "以下の設定を適用します："
for package in "${PACKAGES[@]}"; do
    if [ -d "$package" ]; then
        echo "  - $package"
    fi
done
echo ""

# 確認
read -p "続行しますか? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "キャンセルしました"
    exit 0
fi

# 既存のファイルをバックアップ
BACKUP_DIR="$HOME/.dotfiles_backup_$(date +%Y%m%d_%H%M%S)"
echo ""
echo "既存の設定ファイルを $BACKUP_DIR にバックアップします..."

for package in "${PACKAGES[@]}"; do
    if [ -d "$package" ]; then
        # パッケージ内のファイルをチェック
        for file in "$package"/.*; do
            [ -e "$file" ] || continue
            filename=$(basename "$file")
            target="$HOME/$filename"

            # ファイルが存在し、かつシンボリックリンクでない場合
            if [ -e "$target" ] && [ ! -L "$target" ]; then
                mkdir -p "$BACKUP_DIR"
                echo "  バックアップ: $target"
                mv "$target" "$BACKUP_DIR/"
            fi
        done
    fi
done

# Stow を実行
echo ""
echo "設定を適用しています..."
for package in "${PACKAGES[@]}"; do
    if [ -d "$package" ]; then
        echo "  適用中: $package"
        stow -v -t ~ "$package"
    fi
done

echo ""
echo "=== インストール完了 ==="
echo ""
echo "シンボリックリンクが作成されました。"
if [ -d "$BACKUP_DIR" ]; then
    echo "元のファイルは $BACKUP_DIR にバックアップされています。"
fi
echo ""

# VSCode 拡張機能のインストール確認
if [ -d "vscode" ] && [ -f "vscode/install-extensions.sh" ]; then
    echo ""
    read -p "VSCode 拡張機能もインストールしますか? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        bash vscode/install-extensions.sh
    else
        echo "VSCode 拡張機能のインストールをスキップしました"
        echo "後で手動でインストールする場合："
        echo "  cd vscode && ./install-extensions.sh"
    fi
fi

echo ""
echo "アンインストールする場合："
echo "  stow -D -t ~ bash git vim claude vscode nvim"
