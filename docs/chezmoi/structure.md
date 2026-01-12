# Chezmoi ディレクトリ構造

## 概要

```
chezmoi/
├── shells/          # シェル設定
│   ├── bashrc
│   ├── zshrc
│   └── profile
├── git/             # Git 設定
│   ├── gitconfig
│   └── gitconfig.tmpl
├── cli/             # CLI ツール設定
│   ├── fd/          # fd (find 代替)
│   ├── ripgrep/     # ripgrep (grep 代替)
│   ├── starship/    # Starship プロンプト
│   ├── ghq/         # ghq (リポジトリ管理)
│   └── zoxide/      # zoxide (cd 代替)
├── terminals/       # ターミナル設定
│   ├── wezterm/     # WezTerm
│   └── windows-terminal/  # Windows Terminal
├── editors/         # エディタ設定
│   ├── vscode/      # VS Code
│   ├── cursor/      # Cursor
│   ├── zed/         # Zed
│   └── nvim/        # Neovim
├── llms/            # LLM ツール設定
│   ├── claude/      # Claude
│   ├── codex/       # OpenAI Codex
│   ├── cursor/      # Cursor Rules
│   └── gemini/      # Gemini
├── github/          # GitHub 設定
│   ├── workflows/   # GitHub Actions
│   ├── ISSUE_TEMPLATE/
│   └── CODEOWNERS
├── ssh/             # SSH 設定テンプレート
│   └── config.tmpl
├── dot_config/      # ~/.config に配置されるファイル
│   └── git/hooks/   # Git hooks
└── .chezmoiscripts/ # デプロイスクリプト
    ├── run_onchange_deploy.ps1  # Windows 用
    └── run_onchange_deploy.sh   # Unix/Linux 用
```

## カテゴリ別説明

### shells/

シェルの設定ファイル。bash, zsh, POSIX sh の設定を管理。

### git/

Git のグローバル設定。テンプレート機能 (`*.tmpl`) でマシン固有の設定も対応。

### cli/

コマンドラインツールの設定。

| ツール   | 説明                            |
| -------- | ------------------------------- |
| fd       | find の代替、高速ファイル検索   |
| ripgrep  | grep の代替、高速テキスト検索   |
| starship | クロスシェルプロンプト          |
| ghq      | リポジトリ管理                  |
| zoxide   | cd の代替、ディレクトリジャンプ |

### terminals/

ターミナルエミュレータの設定。

| ターミナル       | 設定ファイル    |
| ---------------- | --------------- |
| WezTerm          | `wezterm.lua`   |
| Windows Terminal | `settings.json` |

### editors/

エディタの設定。

| エディタ | 設定内容                                         |
| -------- | ------------------------------------------------ |
| VS Code  | settings.json, keybindings.json, extensions.json |
| Cursor   | 同上                                             |
| Zed      | settings.json, keymap.json                       |
| Neovim   | init.lua, lua/                                   |

### llms/

LLM ツールの設定。

| ツール | 設定ファイル             |
| ------ | ------------------------ |
| Claude | CLAUDE.md, settings.json |
| Codex  | config.toml              |
| Cursor | rules                    |
| Gemini | settings.json            |

### github/

GitHub 関連の設定。Actions workflows, Issue/PR テンプレートなど。

### ssh/

SSH 設定のテンプレート。`.tmpl` 拡張子でマシン固有の設定を生成。

## デプロイメント方式

すべての設定は `.chezmoiscripts/` のスクリプト経由でデプロイされます。

- `run_onchange_deploy.ps1` - Windows (PowerShell)
- `run_onchange_deploy.sh` - Unix/Linux/WSL/DevContainer

`.chezmoiignore` でディレクトリ自体は無視し、スクリプトで適切な場所に配置します。

## ファイル命名規則

chezmoi の命名規則:

| プレフィックス | 意味                              |
| -------------- | --------------------------------- |
| `dot_`         | `.` で始まるファイル/ディレクトリ |
| `private_`     | パーミッション 0600               |
| `executable_`  | 実行可能フラグ                    |
| `.tmpl`        | テンプレート（変数展開）          |
