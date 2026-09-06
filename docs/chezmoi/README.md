# Chezmoi ドキュメント

chezmoi によるユーザー設定管理の詳細ドキュメント。

## 目次

- [概要](#概要)
- [インストールと適用](./usage.md)
- [ディレクトリ構造](./structure.md)
- [キーバインド統一方針](./keybindings.md)
- [Neovim の設定と検証](./neovim.md)
- [Neovim 最新化調査・採否](./neovim-modernization-audit.md)
- [シークレット管理](./secrets.md)
- [1Password CLI 運用](../1password/README.md)

## 概要

chezmoi はユーザーレベルの dotfiles（設定ファイル）を管理します。

**管理対象:**

- シェル設定 (bash, zsh, starship)
- Git 設定
- CLI ツール設定 (fd, ripgrep, ghq, zoxide)
- ターミナル設定 (WezTerm, Windows Terminal)
- エディタ設定 (VS Code, Cursor, Zed, Neovim)
- LLM ツール設定 (Claude, Codex, Cursor, Gemini)
- SSH 設定テンプレート
- GitHub 設定 (workflows, templates)

**役割分担:**

| 役割                   | ツール                                             |
| ---------------------- | -------------------------------------------------- |
| パッケージインストール | Nix (macOS/Linux/WSL)、catalog の Windows provider |
| ユーザー設定           | Chezmoi                                            |
| シェル統合             | zshrc (chezmoi でデプロイ)                         |

## クイックスタート

### Windows

```powershell
# クローン済みリポジトリのルートで実行
winget install -e --id twpayne.chezmoi
chezmoi init --source "$PWD/chezmoi"
chezmoi --source "$PWD/chezmoi" diff
chezmoi --source "$PWD/chezmoi" apply
```

### macOS / WSL / Linux

```bash
# クローン済みリポジトリのルートで実行
chezmoi init --source "$PWD/chezmoi"
chezmoi --source "$PWD/chezmoi" diff
chezmoi --source "$PWD/chezmoi" apply
```

`--source-path` はサブディレクトリ指定ではなくターゲット解釈を変えるフラグです。詳細・installer 経由の適用は [usage.md](./usage.md) を参照。
