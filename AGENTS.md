# AGENTS

Purpose: repo-level workflow notes.

📖 アーキテクチャ詳細: [docs/architecture.md](./docs/architecture.md)

## Repository Structure

```
dotfiles/
├── chezmoi/                # Chezmoi source for user dotfiles (shell/git/starship/vscode/LLM)
├── nix/                    # NixOS configuration (no Home Manager)
│   ├── flakes/             # Flake inputs/outputs, treefmt
│   ├── hosts/              # Host-specific configs (WSL)
│   ├── profiles/           # Reusable host profiles
│   ├── modules/            # Custom NixOS modules
│   ├── packages/           # Package sets for nix profile
│   ├── lib/                # Helper functions
│   ├── overlays/           # Nixpkgs overlays
│   └── templates/          # Project templates
├── Taskfile.yml            # Task runner (WSL 経由で nix fmt, pre-commit 等を実行)
├── scripts/                # All scripts (see scripts/AGENTS.md)
│   ├── sh/                 # Shell scripts (Linux/WSL)
│   │   ├── update.sh           # Daily update script
│   │   ├── nixos-wsl-postinstall.sh
│   │   └── treefmt.sh
│   └── powershell/         # PowerShell scripts (Windows)
│       ├── apply-chezmoi.ps1       # Apply chezmoi dotfiles (auto-installs chezmoi)
│       ├── update-windows-settings.ps1  # Apply winget packages
│       ├── update-wslconfig.ps1    # Apply .wslconfig
│       ├── export-settings.ps1     # Export Windows settings
│       └── format-ps1.ps1          # Format PowerShell scripts
├── windows/                # Windows-side config files
│   ├── winget/             # Package management
│   └── .wslconfig          # WSL configuration
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

## Chezmoi

ユーザーレベルの dotfiles を `chezmoi/` で管理（shell, git, terminal, VS Code, LLM configs）。

📖 詳細: [docs/chezmoi/](./docs/chezmoi/)

## Formatting & Pre-commit

treefmt を使用して複数のフォーマッターを統一管理。NixOS/WSL 側で `nix fmt` を実行。

### Quick Reference

| 設定             | ファイル                             |
| ---------------- | ------------------------------------ |
| Source of truth  | `.treefmt.toml`                      |
| Nix integration  | `nix/flakes/treefmt.nix`             |
| Task runner      | `Taskfile.yml`                       |
| Pre-commit hooks | `.pre-commit-config.yaml`            |
| 詳細ドキュメント | [docs/formatter/](./docs/formatter/) |

### Usage

```bash
# Via Nix (WSL/NixOS)
nix fmt

# Via Taskfile (Windows → WSL)
task fmt          # nix fmt を実行
task lint         # pre-commit を実行
task commit -- "message"  # フォーマット + コミット
task sync -- "message"    # 全部やって push
```

### Prerequisites

PowerShell formatting requires PSScriptAnalyzer:

```powershell
pwsh -NoProfile -Command "Install-Module PSScriptAnalyzer -Scope CurrentUser"
```

### Taskfile によるタスク管理

`Taskfile.yml` で WSL 経由の NixOS コマンドを実行:

- `task fmt`: nix fmt を実行
- `task lint`: pre-commit を実行
- `task commit`: フォーマット + lint + コミット
- `task rebuild`: nixos-rebuild switch

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
