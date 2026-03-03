# Chezmoi Dotfiles

Cross-platform dotfiles management using chezmoi.

📖 詳細なドキュメント: [docs/chezmoi/](../docs/chezmoi/)

## Directory Structure

```
chezmoi/
├── dot_gitconfig.tmpl  # Git config → ~/.gitconfig (global, all platforms)
├── dot_claude/  # Claude Code config → ~/.claude/
├── dot_codex/   # Codex CLI config → ~/.codex/
├── dot_cursor/  # Cursor AI config → ~/.cursor/
├── dot_gemini/  # Gemini CLI config → ~/.gemini/
├── shells/      # Shell configurations (bash, zsh, profile) [via scripts]
├── secret/      # 1Password-managed secret loaders (GH_TOKEN, TAVILY_API_KEY) [via scripts]
├── cli/         # CLI tool configurations (fd, ripgrep, starship, ghq, zoxide) [via scripts]
├── terminals/   # Terminal emulator configurations (wezterm, windows-terminal) [via scripts]
├── editors/     # Editor configurations (vscode, cursor, zed) [via scripts]
├── github/      # GitHub configs (workflows, templates, etc) [via scripts]
├── ssh/         # SSH config templates [via scripts]
└── .chezmoiscripts/  # Deployment scripts
```

## Deployment Methods

| Directory | Method             | Description                 |
| --------- | ------------------ | --------------------------- |
| `dot_*`   | chezmoi native     | 直接 `~/<name>/` にデプロイ |
| Others    | `.chezmoiscripts/` | スクリプト経由でデプロイ    |

## Architecture

### Deployment Method

All configurations are deployed via `.chezmoiscripts/run_onchange_deploy.*`:

- `run_onchange_deploy.ps1` - Windows (PowerShell)
- `run_onchange_deploy.sh` - Unix/Linux/WSL/DevContainer

### Role Separation

| Role                  | Tool                              |
| --------------------- | --------------------------------- |
| **Installation**      | Nix (Linux/WSL), winget (Windows) |
| **Configuration**     | Chezmoi (this directory)          |
| **Shell Integration** | Nix Home Manager (fzf, zoxide)    |

### Git Hooks

Repository-specific hooks are in `/.githooks/` (not managed by chezmoi).
Global git config (`dot_gitconfig.tmpl`) does NOT set `core.hooksPath`.

## Usage

```bash
# Initialize chezmoi
chezmoi init --source ~/.dotfiles/chezmoi

# Apply configurations
chezmoi apply
```

Windows (example):

```powershell
chezmoi init --source "D:/my_programing/dotfiles/chezmoi"
chezmoi apply
```

## Adding New Configurations

1. Create appropriate subdirectory under the relevant category
2. Add configuration files
3. Update deployment scripts if needed
4. All directories are ignored by chezmoi (see `.chezmoiignore`) and deployed via scripts

Notes:

- `AGENTS.md` / `README.md` are intentionally ignored (docs only)

## .chezmoiignore Patterns

`.chezmoiignore.tmpl` のパターンは**ターゲット名**（テンプレート処理後の名前）に対してマッチする。

### スクリプトの命名規則

| ソース名                                  | ターゲット名            |
| ----------------------------------------- | ----------------------- |
| `run_onchange_install-foo_darwin.sh.tmpl` | `install-foo_darwin.sh` |
| `run_once_before_setup_windows.ps1.tmpl`  | `setup_windows.ps1`     |

- `run_onchange_`, `run_once_`, `run_`, `before_`, `after_` プレフィックスは除去される
- `.tmpl` サフィックスは除去される

### OS フィルタリングの正しい書き方

```
# ✅ 正しい（ターゲット名にマッチ）
{{ if ne .chezmoi.os "darwin" }}
.chezmoiscripts/*_darwin.sh
{{ end }}

# ❌ 間違い（ソース名にマッチしようとしている）
{{ if ne .chezmoi.os "darwin" }}
.chezmoiscripts/*_darwin.sh.tmpl
{{ end }}
```

### 外部コマンド依存ファイルの除外

`lookPath` を使って CLI ツールが未インストールの環境でテンプレートエラーを防ぐ:

```
# op (1Password CLI) が未インストール時は .openclaw/ を無視
{{ if not (lookPath "op") -}}
.openclaw/
{{ end -}}
```

`lookPath "cmd"` はコマンドが PATH になければ空文字列を返す（エラーにならない）。
`onepasswordRead` 等を使うテンプレートファイルを含むディレクトリに対して使用する。

## Platform Support

- Windows (native)
- Linux
- WSL (Windows Subsystem for Linux)
- DevContainer
