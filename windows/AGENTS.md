# AGENTS

Purpose
- Windows-side configuration management, installer helpers, and execution guidance.

## Directory Structure
```
windows/
├── winget/             # Package management (winget export/import)
├── scripts/            # Management scripts
├── .wslconfig          # WSL configuration
└── install-nixos-wsl.* # NixOS WSL installer
```

Note: Windows Terminal settings are managed in Nix at
`nix/profiles/home/programs/terminals/windows-terminal/`

## scripts/

### export-settings.ps1
Export current Windows settings to dotfiles.
- Exports winget package list

### apply-settings.ps1
Apply settings from dotfiles (requires Administrator).

**Architecture:**
```
┌──────────────────────────────────────────────────────────────┐
│                         WSL (NixOS)                          │
│  ~/.config/windows-terminal/settings.json                    │
│       ↓ (symlink to /nix/store/...)                          │
│  /nix/store/xxx-windows-terminal-settings.json               │
└──────────────────────────────────────────────────────────────┘
                            │
                            │ wsl -d NixOS -- cat ...
                            ↓
┌──────────────────────────────────────────────────────────────┐
│                  apply-settings.ps1                          │
│  1. Read JSON content via WSL (resolves symlinks)            │
│  2. Write directly to Windows Terminal LocalState            │
└──────────────────────────────────────────────────────────────┘
                            │
                            ↓
┌──────────────────────────────────────────────────────────────┐
│  %LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_xxx\      │
│    LocalState\settings.json                                  │
└──────────────────────────────────────────────────────────────┘
```

**Why copy instead of symlink?**
- Home Manager creates symlinks pointing to `/nix/store/`
- Windows cannot resolve WSL symlinks to nix store paths
- Solution: Read content via `wsl cat` and copy to Windows

**Usage:**
```powershell
# Full apply (requires Administrator)
.\windows\scripts\apply-settings.ps1

# Skip winget package installation
.\windows\scripts\apply-settings.ps1 -SkipWinget

# Specify different WSL distro
.\windows\scripts\apply-settings.ps1 -WslDistro Ubuntu
```

**Prerequisites:**
- Run `sudo nixos-rebuild switch` in WSL first to generate settings
- PowerShell must be run as Administrator

**Parameters:**
- `-SkipWinget`: Skip winget package installation
- `-WslDistro`: WSL distribution name (default: NixOS)

## install-nixos-wsl.ps1

Main installer script for NixOS on WSL.

### Sync Modes
| Mode | Description |
|------|-------------|
| `link` (default) | Creates symlink ~/.dotfiles -> Windows dotfiles path |
| `repo` | Copies dotfiles to ~/.dotfiles via rsync |
| `nix` | Copies only nix/ directory |
| `none` | No sync, manual setup required |

### Key Parameters
- `-SyncMode`: Sync mode (default: link)
- `-SyncBack`: What to sync back (default: lock for link mode)
- `-Force`: Allow overwriting existing ~/.dotfiles

Wrapper
- Reason: Windows built-in `sudo` may try to execute `.ps1` as a Win32 app and fail (`0x800700C1`).
- Fix: use the CMD wrapper to invoke PowerShell explicitly.

Recommended usage for AI agents
- Prefer `sudo .\install-nixos-wsl.cmd` to ensure elevated execution works without interactive prompts.
- Alternatively, run an elevated PowerShell and execute `.\install-nixos-wsl.ps1` directly.
