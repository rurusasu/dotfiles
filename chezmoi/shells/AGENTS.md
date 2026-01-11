# Shell Configurations

Shell configuration files for bash, zsh, and POSIX profile.

## Files

| File | Deployed To | Description |
|------|-------------|-------------|
| `bashrc` | `~/.bashrc` | Bash shell configuration |
| `zshrc` | `~/.zshrc` | Zsh shell configuration |
| `profile` | `~/.profile` | POSIX profile (login shell) |

## Features

### Common Features (both bash/zsh)
- Aliases: `grep` → `rg`, `find` → `fd`
- PATH additions: `~/bin`, `~/.local/bin`
- Tool integrations: starship, zoxide, fzf
- NVM (Node Version Manager) support

### Zsh-specific
- Kubernetes aliases (k, kgn, kgp, kgs)
- NixOS rebuild aliases (nrs, nrt, nrb)
- Advanced fzf keybindings (Alt+Z, Alt+D, Alt+T, Alt+R)

## Shell Integration

Shell integrations for fzf and zoxide are managed by **Nix Home Manager**, not these files directly. These files provide:
- Environment variables
- Aliases
- Custom functions

## Platform Notes

- **Windows**: These files are deployed but typically used in WSL/Git Bash
- **Linux/WSL**: Primary target platform
- **DevContainer**: Used for development containers
