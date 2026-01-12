# AGENTS

Purpose: repo-level workflow notes.

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
├── .mise.toml              # mise tool configuration (treefmt, pre-commit, etc.)
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

```
Windows                              WSL (NixOS)
────────                             ───────────
install.ps1
    │
    ├─► Download NixOS WSL
    │
    ├─► Import to WSL
    │
    └─► scripts/sh/nixos-wsl-postinstall.sh ──► ~/.dotfiles (symlink)
                                                  │
                                                  ▼
                                             nixos-rebuild switch
                                                  │
                                                  ▼
                                             NixOS configured
```

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

Apply via chezmoi on Windows:

```powershell
chezmoi init --source ~/.dotfiles/chezmoi
chezmoi apply
# 方法1: GitHub から直接取得（クローン不要）
winget install -e --id twpayne.chezmoi
chezmoi init rurusasu/dotfiles --source-path chezmoi
chezmoi apply

# 方法2: ローカルコピーから適用
chezmoi init --source <repo-path>\chezmoi
chezmoi apply

# 方法3: 同梱スクリプトで一括適用
.\scripts\powershell\apply-chezmoi.ps1 -InstallChezmoi
```

### Dry Run (from WSL)

To test build without applying:

```bash
sudo nixos-rebuild dry-build --flake ~/.dotfiles --impure
```

## Chezmoi

User-level dotfiles are managed in `chezmoi/` (shell, git, starship, VS Code settings, terminal configs, LLM configs).

**Note**: クローン不要で GitHub から直接適用可能。

### Windows での適用

```powershell
# 方法1: GitHub から直接取得（クローン不要）
winget install -e --id twpayne.chezmoi
chezmoi init rurusasu/dotfiles --source-path chezmoi
chezmoi apply

# 方法2: ローカルコピーから適用
chezmoi init --source <repo-path>\chezmoi
chezmoi apply

# 方法3: 同梱スクリプトで一括適用
.\scripts\powershell\apply-chezmoi.ps1 -InstallChezmoi
```

### WSL/Linux での適用

```bash
# ~/.dotfiles シンボリックリンクがある場合
chezmoi init --source ~/.dotfiles/chezmoi
chezmoi apply

# GitHub から直接取得（クローン不要）
chezmoi init rurusasu/dotfiles --source-path chezmoi
chezmoi apply
```

Secrets:

- Configure age/gpg in `~/.config/chezmoi/chezmoi.toml`
- Use `chezmoi add --encrypt <path>` to add secrets

## Formatting & Pre-commit

treefmt を使用して複数のフォーマッターを統一管理。mise でツールを管理し、pre-commit でコミット時に自動実行。

### Quick Reference

| 設定 | ファイル |
|------|----------|
| Source of truth | `.treefmt.toml` |
| Nix integration | `nix/flakes/treefmt.nix` |
| Tool versions | `.mise.toml` |
| Pre-commit hooks | `.pre-commit-config.yaml` |
| 詳細ドキュメント | [docs/formatter/](./docs/formatter/) |

### Usage

```bash
# Via Nix (recommended)
nix fmt

# Via mise + treefmt (Windows/Linux)
mise install      # Install tools (treefmt, pre-commit, etc.)
treefmt           # Run formatter
pre-commit run    # Run all hooks manually
```

### Prerequisites

PowerShell formatting requires PSScriptAnalyzer:

```powershell
pwsh -NoProfile -Command "Install-Module PSScriptAnalyzer -Scope CurrentUser"
```

### mise によるツール管理

`.mise.toml` で以下のツールを管理:
- treefmt: 統一フォーマッター
- pre-commit: Git フック管理
- stylua: Lua フォーマッター
- shfmt: Shell フォーマッター

`mise install` で自動インストールされ、postinstall フックで `pre-commit install` も自動実行。

## Terminal Settings Flow

```
┌──────────────────────────────────────────────────────────────┐
│  Chezmoi (source of truth)                                   │
│  chezmoi/AppData/Local/.../settings.json                    │
│  chezmoi/dot_config/wezterm/wezterm.lua                      │
└──────────────────────────────────────────────────────────────┘
                            │
                            │ chezmoi apply (Windows)
                            ↓
┌──────────────────────────────────────────────────────────────┐
│                         Windows                              │
│  %LOCALAPPDATA%\...\WindowsTerminal\settings.json            │
│  %USERPROFILE%\.config\wezterm\wezterm.lua                   │
└──────────────────────────────────────────────────────────────┘
                            │
                            │ chezmoi apply (WSL/Linux)
                            ↓
┌──────────────────────────────────────────────────────────────┐
│                         WSL/Linux                            │
│  ~/.config/wezterm/wezterm.lua                               │
└──────────────────────────────────────────────────────────────┘
```

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
