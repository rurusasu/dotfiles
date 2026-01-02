# AGENTS

Purpose: Home Manager profiles and source files.
Expected contents:
- default.nix: main entry point, imports programs/ and bash/.
- bash/: bash configuration files (.bashrc, .profile, .bash_logout).
- programs/: tool-specific Home Manager modules.
Notes:
- nixvim config is in profiles/nixvim/, imported from default.nix.
- ~/.dotfiles is a symlink to Windows-side dotfiles (created by postinstall).

## Shell Aliases (zsh)

### NixOS Rebuild
| Alias | Command | Description |
|-------|---------|-------------|
| `nrs` | `sudo nixos-rebuild switch --flake ~/.dotfiles --impure` | Rebuild and switch to new configuration |
| `nrt` | `sudo nixos-rebuild test --flake ~/.dotfiles --impure` | Build and activate without adding to boot menu |
| `nrb` | `sudo nixos-rebuild boot --flake ~/.dotfiles --impure` | Build and add to boot menu (activates on next boot) |

Note: `--impure` is required for dynamic dotfiles path resolution via `mkOutOfStoreSymlink`.

Tab completion is available for additional options: `--show-trace`, `--verbose`, `--upgrade`, `--update-input`
