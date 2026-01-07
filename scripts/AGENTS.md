# AGENTS

Purpose: Shell scripts for NixOS setup, maintenance, and Windows settings management.

## Directory Structure
```
scripts/
├── sh/                           # Shell scripts (Linux/WSL)
│   ├── update.sh                 # Daily update script (NixOS rebuild + Windows settings)
│   ├── nixos-wsl-postinstall.sh  # Post-install setup for NixOS WSL
│   └── treefmt.sh                # Code formatting
└── powershell/                   # PowerShell scripts (Windows)
    ├── update-windows-settings.ps1  # Apply terminal settings to Windows (Admin)
    ├── update-wslconfig.ps1      # Apply .wslconfig to Windows
    ├── export-settings.ps1       # Export Windows settings to dotfiles
    └── format-ps1.ps1            # Format PowerShell scripts via PSScriptAnalyzer

Note: install.ps1 is in the repository root (auto-elevates to admin).
```

## Shell Scripts (Linux/WSL)

### nixos-wsl-postinstall.sh

Post-install setup script run after NixOS WSL import.

#### Sync Modes
| Mode | Description |
|------|-------------|
| `link` (default) | Creates symlink ~/.dotfiles -> Windows dotfiles path |
| `repo` | Copies dotfiles to ~/.dotfiles via rsync |
| `nix` | Copies only nix/ directory |
| `none` | No sync, manual setup required |

#### Key Options
- `--sync-mode <mode>`: Sync mode (default: link)
- `--sync-source <path>`: Source directory (default: script's parent dir)
- `--repo-dir <path>`: Target directory (default: /home/<user>/.dotfiles)
- `--flake-name <name>`: Flake host name (default: nixos)
- `--force`: Allow overwriting existing repo-dir

#### Flow
1. Create ~/.dotfiles (symlink or copy based on sync-mode)
2. Generate user/host nix files if missing
3. Run nixos-rebuild switch
4. Sync back flake.lock if sync-back=lock

## PowerShell Scripts (Windows)

### update-wslconfig.ps1

Apply `.wslconfig` from `windows/.wslconfig` to `%USERPROFILE%\.wslconfig`.

**Usage:**
```powershell
.\scripts\powershell\update-wslconfig.ps1
wsl --shutdown  # To apply changes
```

### update-windows-settings.ps1

Apply settings from dotfiles to Windows (requires Administrator).

**Architecture:**
```
┌──────────────────────────────────────────────────────────────┐
│  Nix Configuration (source of truth)                         │
│  nix/profiles/home/programs/terminals/windows-terminal/      │
│  nix/profiles/home/programs/terminals/wezterm/               │
└──────────────────────────────────────────────────────────────┘
                            │
                            │ nixos-rebuild switch
                            ↓
┌──────────────────────────────────────────────────────────────┐
│                         WSL (NixOS)                          │
│  ~/.config/windows-terminal/settings.json                    │
│  ~/.config/wezterm/wezterm.lua                               │
│       ↓ (symlinks to /nix/store/...)                         │
└──────────────────────────────────────────────────────────────┘
                            │
                            │ wsl -d NixOS -- cat ...
                            ↓
┌──────────────────────────────────────────────────────────────┐
│                  update-windows-settings.ps1                 │
│  1. Read content via WSL (resolves symlinks)                 │
│  2. Write directly to Windows config locations               │
└──────────────────────────────────────────────────────────────┘
                            │
                            ↓
┌──────────────────────────────────────────────────────────────┐
│  Windows Terminal:                                           │
│    %LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_xxx\    │
│      LocalState\settings.json                                │
│  WezTerm:                                                    │
│    %USERPROFILE%\.config\wezterm\wezterm.lua                 │
└──────────────────────────────────────────────────────────────┘
```

**Why copy instead of symlink?**
- Home Manager creates symlinks pointing to `/nix/store/`
- Windows cannot resolve WSL symlinks to nix store paths
- Solution: Read content via `wsl cat` and copy to Windows

**Usage:**
```powershell
# Full apply (requires Administrator)
.\scripts\powershell\update-windows-settings.ps1

# Skip winget package installation
.\scripts\powershell\update-windows-settings.ps1 -SkipWinget

# Specify different WSL distro
.\scripts\powershell\update-windows-settings.ps1 -WslDistro Ubuntu
```

**Prerequisites:**
- Run `sudo nixos-rebuild switch` in WSL first to generate settings
- PowerShell must be run as Administrator

**Parameters:**
- `-SkipWinget`: Skip winget package installation
- `-WslDistro`: WSL distribution name (default: NixOS)

### export-settings.ps1

Export current Windows settings to dotfiles.

**What it exports:**
- Winget package list to `windows/winget/packages.json`

**Note:** Windows Terminal and WezTerm settings are managed in Nix:
- `nix/profiles/home/programs/terminals/windows-terminal/`
- `nix/profiles/home/programs/terminals/wezterm/`

**Usage:**
```powershell
.\scripts\powershell\export-settings.ps1
```
