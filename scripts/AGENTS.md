# AGENTS

Purpose: Shell scripts for NixOS setup and maintenance.

## nixos-wsl-postinstall.sh

Post-install setup script run after NixOS WSL import.

### Sync Modes
| Mode | Description |
|------|-------------|
| `link` (default) | Creates symlink ~/.dotfiles -> Windows dotfiles path |
| `repo` | Copies dotfiles to ~/.dotfiles via rsync |
| `nix` | Copies only nix/ directory |
| `none` | No sync, manual setup required |

### Key Options
- `--sync-mode <mode>`: Sync mode (default: link)
- `--sync-source <path>`: Source directory (default: script's parent dir)
- `--repo-dir <path>`: Target directory (default: /home/<user>/.dotfiles)
- `--flake-name <name>`: Flake host name (default: nixos)
- `--force`: Allow overwriting existing repo-dir

### Flow
1. Create ~/.dotfiles (symlink or copy based on sync-mode)
2. Generate user/host nix files if missing
3. Run nixos-rebuild switch
4. Sync back flake.lock if sync-back=lock
