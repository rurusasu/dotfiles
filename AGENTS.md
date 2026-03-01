# AGENTS

Purpose: repo-level workflow notes.

📖 アーキテクチャ詳細: [docs/architecture.md](./docs/architecture.md)

## Repository Structure

```
dotfiles/
├── chezmoi/                # Chezmoi source for user dotfiles
│   ├── dot_claude/         # → ~/.claude/ (Claude Code)
│   ├── dot_codex/          # → ~/.codex/ (Codex CLI)
│   ├── dot_cursor/         # → ~/.cursor/ (Cursor AI)
│   ├── dot_gemini/         # → ~/.gemini/ (Gemini CLI)
│   ├── dot_config/         # → ~/.config/ (XDG Base Directory)
│   │   └── git/            # → ~/.config/git/ (Git config & hooks)
│   └── ...                 # その他 (shells, cli, terminals, editors 等)
├── nix/                    # NixOS configuration (flake-parts)
│   ├── flake/              # Flake-parts modules (entry point)
│   │   ├── treefmt.nix     # Code formatter configuration
│   │   └── packages.nix    # Packages and devShell definition
│   ├── core/               # Shared system configurations
│   ├── hosts/              # Host-specific configs (WSL/Linux)
│   ├── modules/            # Reusable NixOS modules
│   └── templates/          # Flake templates
├── docker/                 # Docker コンテナ定義
│   └── openclaw/           # Telegram AI ゲートウェイ (see docker/openclaw/AGENTS.md)
├── scripts/                # All scripts (see scripts/AGENTS.md)
│   ├── sh/                 # Shell scripts (Linux/WSL)
│   └── powershell/         # PowerShell scripts (Windows)
│       └── handlers/       # Setup handlers (see handlers/AGENTS.md)
├── tasks/                  # Taskfile tasks
│   └── lint/               # Cross-platform linting (see docs/taskfile/lint.md)
├── windows/                # Windows-side config files
│   ├── winget/             # winget package list
│   └── npm/                # npm global package list
├── .pre-commit-config.yaml # Pre-commit hooks configuration
├── .secrets.baseline       # detect-secrets baseline
├── .cz.toml                # Commitizen config
├── _typos.toml             # Typos spell checker config
├── Taskfile.yml            # Task runner (WSL 経由で nix fmt 等を実行)
└── install.ps1             # NixOS WSL installer (auto-elevates to admin)
```

## Setup Flow

セットアップフロー図は [docs/architecture.md](./docs/architecture.md) を参照。

## Testing Changes

### Initial Setup / Full Rebuild (from Windows)

Run from admin PowerShell when setting up fresh or after major changes:

```powershell
sudo pwsh -NoProfile -ExecutionPolicy Bypass -File install.ps1
```

### Incremental Updates (from WSL)

After ~/.dotfiles symlink is set up, run directly from WSL:

```bash
nrs  # alias for: sudo nixos-rebuild switch --flake ~/.dotfiles --impure
```

Since ~/.dotfiles points to Windows-side dotfiles, changes made in Windows are immediately available in WSL without any sync step.

### Apply Terminal Settings (Windows)

chezmoi で Windows に設定を適用。詳細は [docs/chezmoi/](./docs/chezmoi/) を参照。

```powershell
# GitHub から直接取得（推奨）
chezmoi init rurusasu/dotfiles --source-path chezmoi && chezmoi apply

# 同梱スクリプトで一括適用
.\scripts\powershell\apply-chezmoi.ps1 -InstallChezmoi
```

### Dry Run (from WSL)

To test build without applying:

```bash
sudo nixos-rebuild dry-build --flake ~/.dotfiles --impure
```

### PowerShell Tests (Windows)

PowerShell テストは Taskfile で統一管理されています（`task commit` で自動実行）。

```powershell
# Taskfile 経由（推奨）
task test:powershell  # PSScriptAnalyzer lint + Pester tests + bats tests

# 直接実行
cd scripts/powershell/tests
.\Invoke-Tests.ps1 -All -IncludeBats  # 全テスト（Pester + bats）
.\Invoke-Tests.ps1                     # デフォルト（scripts/powershell/tests のみ）
.\Invoke-Tests.ps1 -MinimumCoverage 0  # カバレッジチェックなし（高速）
```

**テスト対象ディレクトリ:**

- `scripts/powershell/tests/` - Pester テスト（ハンドラー、ライブラリ）

## Chezmoi

ユーザーレベルの dotfiles を `chezmoi/` で管理（shell, git, terminal, VS Code, LLM configs）。

📖 詳細: [docs/chezmoi/](./docs/chezmoi/)

## Package + Config Workflow (New Package Task)

When asked to install a new package and place its config:

1. Decide target platform/tool:
   - NixOS/WSL system packages → `nix/core/cli.nix` (see `nix/AGENTS.md`)
   - Windows packages → `windows/winget/packages.json` (see `windows/winget/AGENTS.md`)
   - Windows npm globals → `windows/npm/packages.json` (see `windows/npm/AGENTS.md`)
2. Place configuration in `chezmoi/` under the relevant category (see `chezmoi/AGENTS.md`).
3. Apply changes:
   - NixOS/WSL: `nrs` or `nixos-rebuild switch --flake ~/.dotfiles --impure`
   - Windows: `.\scripts\powershell\update-windows-settings.ps1`
   - Chezmoi: `chezmoi apply` or `.\scripts\powershell\apply-chezmoi.ps1 -InstallChezmoi`

## Formatting & Pre-commit

treefmt を使用して複数のフォーマッターを統一管理。NixOS/WSL 側で `nix fmt` を実行。

### Quick Reference

| 設定             | ファイル                             |
| ---------------- | ------------------------------------ |
| Source of truth  | `.treefmt.toml`                      |
| Nix integration  | `nix/flake/treefmt.nix`              |
| Git hooks        | `.pre-commit-config.yaml`            |
| Task runner      | `Taskfile.yml`                       |
| 詳細ドキュメント | [docs/formatter/](./docs/formatter/) |

### Pre-commit Hooks

`.pre-commit-config.yaml` で一元管理。nixos-rebuild 後に自動インストールされます。

> ⚠️ **コミットは必ず `task commit` か WSL 経由で行うこと**
> `.git/hooks/pre-commit` は NixOS の nix store パスを参照するため、
> Windows から直接 `git commit` すると hook が失敗します。

📖 詳細: [docs/git/commit.md](./docs/git/commit.md)

### Usage

```bash
# コミット（推奨）
task commit -- "メッセージ"   # fmt → pre-commit → git commit (WSL経由)
task sync   -- "メッセージ"   # commit + push

# Via Nix (WSL/NixOS)
nix fmt                       # フォーマット（auto-fix含む）
pre-commit run --all-files    # 手動で全フック実行

# Via Taskfile (Windows → WSL/Windows)
task --list           # 利用可能なタスク一覧
```

## Linting

クロスプラットフォーム対応の lint システム。全 linter は Nix で提供され、Windows/Linux/Mac で同一設定で実行可能。

📖 詳細: [docs/taskfile/lint.md](./docs/taskfile/lint.md)

```powershell
# 全 linter 実行
task lint:all

# 個別 linter
task lint:shellcheck       # Shell script
task lint:statix           # Nix
task lint:psscriptanalyzer # PowerShell
task lint:markdownlint     # Markdown
task lint:typos            # Spell check
task lint:gitleaks         # Secret detection
```

## AI Agent Skills

AI コーディングエージェント (Claude Code, Codex CLI, Gemini CLI, Cursor) のスキルは `chezmoi` で管理。

- Source of truth: `chezmoi/dot_claude/skills/`
- 同期設定: `chezmoi/.chezmoidata/skills_sync.yaml`
- 自動同期: `chezmoi/.chezmoiscripts/run_after_sync-agent-skills_windows.ps1.tmpl` / `chezmoi/.chezmoiscripts/run_after_sync-agent-skills_linux.sh.tmpl`

運用:

```powershell
# dotfiles を更新 + 適用（既定動作）
chezmoi update

# 必要なら明示適用
chezmoi apply --force
```

## Terminal Settings Flow

ターミナル設定の適用フローについては [docs/chezmoi/structure.md](./docs/chezmoi/structure.md) を参照。

## Key Paths

| Location                                                                                          | Description                                          |
| ------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| `chezmoi/`                                                                                        | Chezmoi source for user dotfiles                     |
| `~/.dotfiles`                                                                                     | Symlink to Windows dotfiles (created by postinstall) |
| `nixosConfigurations.nixos`                                                                       | Flake attribute for WSL host                         |
| `/mnt/d/.../dotfiles`                                                                             | Actual Windows-side dotfiles location                |
| `scripts/sh/`                                                                                     | Shell scripts for Linux/WSL                          |
| `scripts/powershell/`                                                                             | PowerShell scripts for Windows                       |
| `windows/`                                                                                        | Windows-side configuration files                     |
| `chezmoi/dot_config/wezterm/wezterm.lua`                                                          | WezTerm settings                                     |
| `chezmoi/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json` | Windows Terminal settings                            |
