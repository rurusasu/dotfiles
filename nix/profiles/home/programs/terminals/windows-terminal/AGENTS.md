# AGENTS

Purpose: Windows Terminal configuration via Nix.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              Nix (WSL)                                  │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  default.nix                                                      │  │
│  │  (Nix expression)                                                 │  │
│  │     ↓                                                             │  │
│  │  nixos-rebuild switch                                             │  │
│  │     ↓                                                             │  │
│  │  /nix/store/xxx-windows-terminal-settings.json                    │  │
│  │     ↓ (symlink)                                                   │  │
│  │  ~/.config/windows-terminal/settings.json                         │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ wsl cat (read via WSL)
                                    ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                            Windows                                      │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  apply-settings.ps1                                               │  │
│  │     ↓ (copy content)                                              │  │
│  │  %LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_xxx\           │  │
│  │    LocalState\settings.json                                       │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

## Data Flow

1. **Edit**: Modify `default.nix` (Nix expression)
2. **Build**: Run `sudo nixos-rebuild switch` in WSL
3. **Generate**: Nix builds JSON in `/nix/store/`, Home Manager symlinks to `~/.config/`
4. **Apply**: Run `apply-settings.ps1` in Windows (Administrator)
5. **Copy**: Script reads JSON via `wsl cat` and writes to Windows Terminal's LocalState

## Why Copy Instead of Symlink?

Windows cannot follow WSL symlinks that point to `/nix/store/`.
Home Manager creates: `~/.config/windows-terminal/settings.json` -> `/nix/store/xxx/settings.json`
Windows sees the symlink but cannot resolve the nix store path.

Solution: PowerShell script reads the file content via `wsl cat` (which resolves symlinks)
and copies it directly to Windows Terminal's settings location.

## Files

- `default.nix`: Settings defined as Nix attrset, converted to JSON via `builtins.toJSON`

## Configuration

- Alt+C and Alt+Z: Unbound (for fzf integration)
- Default profile: PowerShell Core (elevated)
- Profiles: Windows PowerShell, CMD, Azure Cloud Shell, WSL distros, VS Dev tools, Git Bash

## Usage

```bash
# 1. Edit settings in Nix
vim nix/profiles/home/programs/terminals/windows-terminal/default.nix

# 2. Rebuild NixOS (in WSL)
sudo nixos-rebuild switch --flake /mnt/d/my_programing/dotfiles#nixos --impure

# 3. Apply to Windows (PowerShell as Administrator)
.\windows\scripts\apply-settings.ps1 -SkipWinget
```

## Troubleshooting

If Windows Terminal shows "設定を読み込めませんでした":
1. Check if settings.json exists and is valid JSON
2. Remove broken symlink if present
3. Re-run apply-settings.ps1
