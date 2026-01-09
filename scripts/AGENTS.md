# AGENTS

Purpose: Shell scripts for NixOS setup, maintenance, and Windows package management.

## Directory Structure
```
scripts/
├── sh/                           # Shell scripts (Linux/WSL)
│   ├── update.sh                 # Daily update script (NixOS rebuild + optional winget)
│   ├── nixos-wsl-postinstall.sh  # Post-install setup for NixOS WSL
│   └── treefmt.sh                # Code formatting
└── powershell/                   # PowerShell scripts (Windows)
    ├── update-windows-settings.ps1  # Apply winget packages to Windows (Admin)
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

Apply settings from dotfiles to Windows (winget import only).

Note: Windows Terminal and WezTerm settings are managed by chezmoi:
- `chezmoi/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json`
- `chezmoi/dot_config/wezterm/wezterm.lua`

**Usage:**
```powershell
# Full apply (requires Administrator)
.\scripts\powershell\update-windows-settings.ps1

# Skip winget package installation
.\scripts\powershell\update-windows-settings.ps1 -SkipWinget
```

**Parameters:**
- `-SkipWinget`: Skip winget package installation

### export-settings.ps1

Export current Windows settings to dotfiles.

**What it exports:**
- Winget package list to `windows/winget/packages.json`

**Note:** Windows Terminal and WezTerm settings are managed by chezmoi:
- `chezmoi/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json`
- `chezmoi/dot_config/wezterm/wezterm.lua`

**Usage:**
```powershell
.\scripts\powershell\export-settings.ps1
```
