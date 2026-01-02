# AGENTS

Purpose: repo-level workflow notes.

## Setup Flow

```
Windows                              WSL (NixOS)
────────                             ───────────
install-nixos-wsl.ps1
    │
    ├─► Download NixOS WSL
    │
    ├─► Import to WSL
    │
    └─► nixos-wsl-postinstall.sh ──► ~/.dotfiles (symlink)
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
sudo pwsh -NoProfile -ExecutionPolicy Bypass -File windows/install-nixos-wsl.ps1
```

### Incremental Updates (from WSL)

After ~/.dotfiles symlink is set up, run directly from WSL:

```bash
nrs  # alias for: sudo nixos-rebuild switch --flake ~/.dotfiles --impure
```

Since ~/.dotfiles points to Windows-side dotfiles, changes made in Windows are immediately available in WSL without any sync step.

### Dry Run (from WSL)

To test build without applying:

```bash
sudo nixos-rebuild dry-build --flake ~/.dotfiles --impure
```

## Key Paths

| Location | Description |
|----------|-------------|
| `~/.dotfiles` | Symlink to Windows dotfiles (created by postinstall) |
| `nixosConfigurations.nixos` | Flake attribute for WSL host |
| `/mnt/d/.../dotfiles` | Actual Windows-side dotfiles location |
