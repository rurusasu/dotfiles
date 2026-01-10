# AGENTS

Purpose: repo-level workflow notes.

## Repository Structure

```
dotfiles/
├── chezmoi/                # Chezmoi source for user dotfiles (shell/git/starship/vscode/LLM)
├── nix/                    # NixOS/Home Manager configuration
│   ├── flakes/             # Flake inputs/outputs
│   ├── hosts/              # Host-specific configs
│   ├── home/               # Home Manager base
│   ├── profiles/           # Reusable config profiles
│   ├── modules/            # Custom NixOS modules
│   ├── lib/                # Helper functions
│   ├── overlays/           # Nixpkgs overlays
│   ├── packages/           # Custom packages
│   └── templates/          # Config templates
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

## Formatting

Use treefmt for Nix/JSON/YAML/Markdown/TOML/Lua/Shell/PowerShell:

```bash
nix fmt
```

or:

```bash
./scripts/sh/treefmt.sh
```

To enable automatic formatting on commit:

```bash
pre-commit install
```

PowerShell formatting requires PSScriptAnalyzer:

```powershell
pwsh -NoProfile -Command "Install-Module PSScriptAnalyzer -Scope CurrentUser"
```

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

| Location | Description |
|----------|-------------|
| `chezmoi/` | Chezmoi source for user dotfiles |
| `~/.dotfiles` | Symlink to Windows dotfiles (created by postinstall) |
| `nixosConfigurations.nixos` | Flake attribute for WSL host |
| `/mnt/d/.../dotfiles` | Actual Windows-side dotfiles location |
| `scripts/sh/` | Shell scripts for Linux/WSL |
| `scripts/powershell/` | PowerShell scripts for Windows |
| `windows/` | Windows-side configuration files |
| `chezmoi/dot_config/wezterm/wezterm.lua` | WezTerm settings |
| `chezmoi/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json` | Windows Terminal settings |
