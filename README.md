# Dotfiles

GNU Stow を使った dotfiles の一元管理リポジトリ

## 方針 (Home Manager)

NixOS/WSL を含む複数環境で共通運用するため、ユーザー設定は Home Manager に寄せる方針。
設定は `nix/home/` と `nix/profiles/` 配下で管理します。

非 WSL の NixOS 向けホスト設定は `nix/hosts/` で管理します。

## フォーマット (treefmt)

Nix の整形は treefmt で行います。

```bash
nix fmt
```

```bash
./scripts/treefmt.sh
```

## WSL 設定 (.wslconfig)

`.wslconfig` は `windows/.wslconfig` で管理し、以下で適用します。

```powershell
.\windows\apply-wslconfig.ps1
wsl --shutdown
```

## ディレクトリ構造

```
dotfiles/
├── bash/         # Bash設定 (.bashrc, .profile, .bash_logout)
├── git/          # Git設定 (.gitconfig)
├── vim/          # Vim設定 (.vimrc)
├── claude/       # Claude設定 (.claude.json)
├── nvim/         # Neovim設定 (init.lua, vscode統合)
│   └── .config/nvim/
│       ├── init.lua                # メイン設定ファイル
│       └── lua/
│           └── vscode-config.lua   # VSCode固有設定
├── vscode/       # VSCode設定 (settings.json, keybindings.json, snippets/)
│   ├── .config/Code/User/
│   ├── extensions.json             # 拡張機能リスト（vscode-neovim含む）
│   └── install-extensions.sh       # 拡張機能インストールスクリプト
└── install.sh    # インストールスクリプト
```

## 必要なツール

- **GNU Stow** - dotfiles のシンボリックリンク管理
- **Neovim** - VSCode での Vim エミュレーション（オプション）

```bash
# 必須
sudo apt install stow

# VSCode で Vim を使う場合
sudo apt install neovim
```

## インストール方法

### 全ての設定を適用

```bash
./install.sh
```

### 個別に適用

```bash
# Bash設定のみ
stow -t ~ bash

# Git設定のみ
stow -t ~ git

# Vim設定のみ
stow -t ~ vim

# Claude設定のみ
stow -t ~ claude

# Neovim設定のみ
stow -t ~ nvim

# VSCode設定のみ
stow -t ~ vscode
```

## アンインストール方法

```bash
# 全ての設定を削除
stow -D -t ~ bash git vim claude nvim vscode

# 個別に削除
stow -D -t ~ bash
```

## 新しいマシンでのセットアップ

1. リポジトリをクローン

```bash
cd ~
git clone https://github.com/rurusasu/dotfiles.git
cd dotfiles
```

2. GNU Stow をインストール

```bash
sudo apt install stow
```

3. 設定を適用

```bash
./install.sh
```

## 新しい設定ファイルの追加方法

1. 新しいカテゴリのディレクトリを作成

```bash
mkdir <category>
```

2. 設定ファイルを配置

```bash
cp ~/.<config_file> <category>/.<config_file>
```

3. Stow で適用

```bash
stow -t ~ <category>
```

4. 変更をコミット

```bash
git add <category>
git commit -m "Add <category> configuration"
git push
```

## 設定ファイルの更新方法

1. dotfiles リポジトリ内のファイルを編集（シンボリックリンクなので、ホームディレクトリで編集しても同じ）

2. 変更をコミット

```bash
cd ~/dotfiles
git add .
git commit -m "Update configuration"
git push
```

## Neovim for VSCode (Vim Emulation)

このdotfilesには、VSCodeでNeovimを使用するための設定が含まれています。

### セットアップ手順

**1. Neovimをインストール**

```bash
sudo apt update && sudo apt install -y neovim

# バージョン確認（0.5+推奨、0.9+が理想）
nvim --version
```

**2. dotfilesを適用**

```bash
./install.sh
# nvimが含まれるので、~/.config/nvim/init.luaへシンボリックリンクが作成されます
```

**3. VSCode拡張機能をインストール**

```bash
cd vscode
./install-extensions.sh
# vscode-neovimが自動的にインストールされます
```

**4. VSCodeを再起動**

VSCodeを再起動すると、vscode-neovimが有効になります。

### 主な機能

- **Vim モーション**: hjkl, w/b, f/t, gg/G など全てのVimコマンド
- **Visual モード**: v (character), V (line), Ctrl+v (block)
- **マクロ**: qa でマクロ記録開始、@a で再生
- **VSCode統合**: `<leader>` キー（スペース）でVSCodeコマンドにアクセス

### キーバインド一覧

| キー | 機能 |
|------|------|
| `<Space>ff` | ファイル検索（Quick Open） |
| `<Space>fg` | テキスト検索（Find in Files） |
| `<Space>ca` | コードアクション |
| `<Space>rn` | シンボル名変更 |
| `gd` | 定義へジャンプ |
| `gr` | 参照を表示 |
| `gcc` | 行コメント切替 |
| `<Space>e` | エクスプローラー表示 |
| `<Space>tt` | ターミナル切替 |

完全なキーバインドは `nvim/.config/nvim/lua/vscode-config.lua` を参照。

### カスタマイズ

`nvim/.config/nvim/lua/vscode-config.lua` を編集してキーバインドを追加・変更できます。

### トラブルシューティング

**Q: Neovimが起動しない**
```bash
# 設定ファイルのエラーチェック
nvim --headless -c 'checkhealth' -c 'quit'
```

**Q: Vimコマンドが効かない**
- VSCodeVim拡張機能が無効になっているか確認
- vscode-neovimのみ有効にする

## VSCode 拡張機能の管理

VSCode 拡張機能は **2つの方法** で自動セットアップできます：

### 方法1: Bash スクリプトで自動インストール（推奨）

**使い方：**

```bash
# dotfiles セットアップ時に自動実行（./install.sh 実行時に確認されます）
./install.sh

# または手動で実行
cd vscode
./install-extensions.sh
```

**特徴：**
- ✅ **WSL 対応**: Windows の VSCode/VSCode Insiders/Cursor を自動検出
- ✅ `extensions.json` から自動読み込み
- ✅ 既にインストール済みの拡張機能は自動スキップ
- ✅ `jq` 不要（grep/sed でパース）
- ✅ バックアップ自動作成

**対応エディタ：**
- Visual Studio Code
- Visual Studio Code Insiders
- VSCodium / VSCodium Insiders
- Cursor

### 方法2: VSCode の推奨機能

VSCode は `extensions.json` の `recommendations` を自動的に読み込み、「推奨拡張機能をインストールしますか？」と聞いてくれます。

**使い方：**
1. VSCode を開く
2. 右下に表示される通知から「すべてインストール」をクリック

### 拡張機能の追加

`vscode/extensions.json` を編集：

```json
{
  "recommendations": [
    "ms-python.python",
    "your-new-extension-id"
  ]
}
```

### 現在の拡張機能を保存

```bash
# WSL 環境の場合
cd vscode
./install-extensions.sh  # 拡張機能リストを確認

# 手動で extensions.json を編集
```

## トラブルシューティング

### シンボリックリンクが作成されない場合

既存のファイルがある場合は、まずバックアップしてから削除してください：

```bash
# バックアップを作成
mv ~/.bashrc ~/.bashrc.backup

# Stow を実行
stow -t ~ bash
```

### 設定を元に戻す場合

```bash
stow -D -t ~ bash
mv ~/.bashrc.backup ~/.bashrc
```
