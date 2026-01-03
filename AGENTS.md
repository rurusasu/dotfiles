# AGENTS

Purpose: repo-level workflow notes.

## Repository Structure

```
dotfiles/
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
│       ├── update-windows-settings.ps1  # Apply terminal settings
│       ├── update-wslconfig.ps1    # Apply .wslconfig
│       └── export-settings.ps1     # Export Windows settings
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

### Apply Terminal Settings to Windows

After `nixos-rebuild switch`, apply settings to Windows:

```powershell
# Run as Administrator
.\scripts\powershell\update-windows-settings.ps1
```

### Dry Run (from WSL)

To test build without applying:

```bash
sudo nixos-rebuild dry-build --flake ~/.dotfiles --impure
```

## Terminal Settings Flow

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
│       (symlinks to /nix/store/...)                           │
└──────────────────────────────────────────────────────────────┘
                            │
                            │ scripts/powershell/update-windows-settings.ps1
                            ↓
┌──────────────────────────────────────────────────────────────┐
│                         Windows                              │
│  %LOCALAPPDATA%\...\WindowsTerminal\settings.json            │
│  %USERPROFILE%\.config\wezterm\wezterm.lua                   │
└──────────────────────────────────────────────────────────────┘
```

## Key Paths

| Location | Description |
|----------|-------------|
| `~/.dotfiles` | Symlink to Windows dotfiles (created by postinstall) |
| `nixosConfigurations.nixos` | Flake attribute for WSL host |
| `/mnt/d/.../dotfiles` | Actual Windows-side dotfiles location |
| `scripts/sh/` | Shell scripts for Linux/WSL |
| `scripts/powershell/` | PowerShell scripts for Windows |
| `windows/` | Windows-side configuration files |
| `nix/profiles/home/programs/terminals/` | Terminal settings (Windows Terminal, WezTerm) |
