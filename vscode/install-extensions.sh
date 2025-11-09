#!/bin/bash

# VSCode 拡張機能インストールスクリプト
# extensions.json の recommendations から拡張機能を自動インストール
# WSL 環境で Windows の VSCode CLI を自動検出

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXTENSIONS_JSON="$SCRIPT_DIR/extensions.json"

echo "=== VSCode 拡張機能自動インストール ==="
echo ""

# VSCode CLI を探す
CODE_CMD=""

# 1. システムの code コマンドをチェック
if command -v code &> /dev/null; then
    CODE_CMD="code"
    USE_CMD_EXE=false
    echo "✅ VSCode CLI を検出: code (システム)"
# 2. WSL 環境で Windows の VSCode を探す
elif [[ -n "$WSL_DISTRO_NAME" ]] || [[ -n "$WSLENV" ]]; then
    echo "🔍 WSL 環境を検出しました。Windows の VSCode を探しています..."

    # Windows ユーザーディレクトリを取得
    WIN_USER_DIR=""
    if [[ -d "/mnt/c/Users" ]]; then
        # 最初の実在するユーザーディレクトリを取得（Public以外）
        for user_dir in /mnt/c/Users/*; do
            if [[ -d "$user_dir" ]] && [[ "$(basename "$user_dir")" != "Public" ]] && [[ "$(basename "$user_dir")" != "Default"* ]] && [[ "$(basename "$user_dir")" != "All Users" ]]; then
                WIN_USER_DIR="$user_dir"
                break
            fi
        done
    fi

    if [[ -z "$WIN_USER_DIR" ]]; then
        echo "❌ エラー: Windows ユーザーディレクトリが見つかりません"
        exit 1
    fi

    echo "   Windows ユーザー: $(basename "$WIN_USER_DIR")"

    # VSCode CLI の候補リスト（優先順位順）
    VSCODE_PATHS=(
        "$WIN_USER_DIR/AppData/Local/Programs/Microsoft VS Code/bin/code.cmd"
        "$WIN_USER_DIR/AppData/Local/Programs/Microsoft VS Code Insiders/bin/code-insiders.cmd"
        "$WIN_USER_DIR/AppData/Local/Programs/VSCodium/bin/codium.cmd"
        "$WIN_USER_DIR/AppData/Local/Programs/VSCodium Insiders/bin/codium-insiders.cmd"
        "$WIN_USER_DIR/AppData/Local/Programs/cursor/resources/app/codeBin/code.cmd"
    )

    for vscode_path in "${VSCODE_PATHS[@]}"; do
        if [[ -f "$vscode_path" ]]; then
            # WSL から Windows の .cmd ファイルを実行するため cmd.exe 経由で呼び出す
            # Linux パスを Windows パスに変換
            WIN_PATH=$(wslpath -w "$vscode_path" 2>/dev/null || echo "$vscode_path")
            CODE_CMD="cmd.exe /c \"$WIN_PATH\""
            USE_CMD_EXE=true
            echo "   ✅ 検出: $(basename "$(dirname "$(dirname "$vscode_path")")")"
            break
        fi
    done

    if [[ -z "$CODE_CMD" ]]; then
        echo "❌ エラー: VSCode CLI が見つかりません"
        echo ""
        echo "以下のいずれかをインストールしてください:"
        echo "  - Visual Studio Code: https://code.visualstudio.com/"
        echo "  - VSCode Insiders: https://code.visualstudio.com/insiders/"
        echo "  - VSCodium: https://vscodium.com/"
        echo "  - Cursor: https://cursor.sh/"
        exit 1
    fi
else
    echo "❌ エラー: VSCode CLI (code) が利用できません"
    echo "VSCode のインストール、またはPATHの設定を確認してください"
    exit 1
fi

echo ""

# extensions.json が存在するか確認
if [[ ! -f "$EXTENSIONS_JSON" ]]; then
    echo "❌ エラー: $EXTENSIONS_JSON が見つかりません"
    exit 1
fi

# 現在インストールされている拡張機能を保存
echo "📦 現在の拡張機能をバックアップしています..."
eval "$CODE_CMD" --list-extensions > "$SCRIPT_DIR/extensions-backup-$(date +%Y%m%d_%H%M%S).txt" 2>/dev/null || true

# extensions.json から拡張機能リストを抽出
echo ""
echo "📄 extensions.json から拡張機能を読み込んでいます..."
echo ""

# jq が利用可能な場合は jq を使用
if command -v jq &> /dev/null; then
    echo "   jq を使用して拡張機能を抽出しています..."
    EXTENSIONS=$(jq -r '.recommendations[]' "$EXTENSIONS_JSON" 2>/dev/null || echo "")
else
    echo "   grep/sed を使用して拡張機能を抽出しています..."
    # jq がない場合は grep と sed でパース
    EXTENSIONS=$(grep -o '"[^"]*"' "$EXTENSIONS_JSON" | \
                 grep -v "recommendations" | \
                 sed 's/"//g' | \
                 grep -v "^//" | \
                 grep -v "^$")
fi

if [[ -z "$EXTENSIONS" ]]; then
    echo "⚠️  警告: インストールする拡張機能が見つかりません"
    exit 0
fi

# 拡張機能をインストール
echo ""
echo "⚙️  拡張機能をインストールしています..."
echo ""

INSTALLED_COUNT=0
SKIPPED_COUNT=0
FAILED_COUNT=0

# 拡張機能を配列に変換
IFS=$'\n' read -d '' -r -a extension_array <<< "$EXTENSIONS"

for extension in "${extension_array[@]}"; do
    # 空行とコメントをスキップ
    [[ -z "$extension" ]] && continue
    [[ "$extension" =~ ^// ]] && continue

    # 既にインストールされているかチェック
    if eval "$CODE_CMD" --list-extensions 2>/dev/null | grep -qi "^${extension}$"; then
        echo "   ⏭️  スキップ: $extension (既にインストール済み)"
        ((SKIPPED_COUNT++))
    else
        echo "   📥 インストール中: $extension"
        if eval "$CODE_CMD" --install-extension "$extension" --force 2>/dev/null; then
            ((INSTALLED_COUNT++))
        else
            echo "      ⚠️  警告: $extension のインストールに失敗しました"
            ((FAILED_COUNT++))
        fi
    fi
done

echo ""
echo "=== インストール完了 ==="
echo ""
echo "📊 結果:"
echo "   新規インストール: $INSTALLED_COUNT 個"
echo "   スキップ: $SKIPPED_COUNT 個"
if [[ $FAILED_COUNT -gt 0 ]]; then
    echo "   ⚠️  失敗: $FAILED_COUNT 個"
fi
echo ""
echo "📦 現在インストールされている拡張機能の合計:"
eval "$CODE_CMD" --list-extensions 2>/dev/null | wc -l | xargs echo "   "
