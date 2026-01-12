# Chezmoi ドキュメント

chezmoi によるユーザー設定管理の詳細ドキュメント。

## 目次

- [概要](#概要)
- [インストールと適用](./usage.md)
- [ディレクトリ構造](./structure.md)
- [シークレット管理](./secrets.md)

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

| 役割                   | ツール                            |
| ---------------------- | --------------------------------- |
| パッケージインストール | Nix (Linux/WSL), winget (Windows) |
| ユーザー設定           | Chezmoi                           |
| シェル統合             | Nix Home Manager (fzf, zoxide)    |

## クイックスタート

### Windows

```powershell
# GitHub から直接取得（リポジトリのクローン不要）
winget install -e --id twpayne.chezmoi
chezmoi init rurusasu/dotfiles --source-path chezmoi
chezmoi apply
```

### WSL/Linux

```bash
# ~/.dotfiles シンボリックリンクがある場合
chezmoi init --source ~/.dotfiles/chezmoi
chezmoi apply

# GitHub から直接取得
chezmoi init rurusasu/dotfiles --source-path chezmoi
chezmoi apply
```

詳細は [usage.md](./usage.md) を参照。
