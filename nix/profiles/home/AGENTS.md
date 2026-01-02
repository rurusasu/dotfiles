# AGENTS

Purpose: Home Manager profiles and source files.
Expected contents:
- common.nix: shared Home Manager settings imported by all hosts.
- bash/: .bashrc, .profile, .bash_logout (source files).
- programs/: tool-specific Home Manager modules (vscode/, wezterm/).
Notes:
- nixvim config is in profiles/nixvim/, imported from common.nix.

## Shell Aliases (.bashrc)

### NixOS Rebuild
| Alias | Command | Description |
|-------|---------|-------------|
| `nrs` | `sudo nixos-rebuild switch --flake ~/dotfiles --impure` | Rebuild and switch to new configuration |
| `nrt` | `sudo nixos-rebuild test --flake ~/dotfiles --impure` | Build and activate without adding to boot menu |
| `nrb` | `sudo nixos-rebuild boot --flake ~/dotfiles --impure` | Build and add to boot menu (activates on next boot) |

Note: `--impure` is required for dynamic dotfiles path resolution via `mkOutOfStoreSymlink`.

Tab completion is available for additional options: `--show-trace`, `--verbose`, `--upgrade`, `--update-input`
