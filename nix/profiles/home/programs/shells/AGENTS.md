# Shells Profile

Nix Home Manager configuration for shell environments.

## Packages

| Package | Description |
|---------|-------------|
| `bash` | Bourne Again Shell |
| `zsh` | Z Shell |
| `starship` | Cross-shell prompt |

## Role Separation

| Aspect | Managed By |
|--------|------------|
| **Installation** | Nix (this file) |
| **Shell configs** (bashrc, zshrc) | Chezmoi (`chezmoi/shells/`) |
| **Starship config** | Chezmoi (`chezmoi/cli/starship/`) |

## Starship Integration

Starship is enabled via `programs.starship.enable = true`. This:
- Installs the starship package
- Adds shell initialization to bashrc/zshrc automatically

The actual prompt configuration (`starship.toml`) is managed by chezmoi.

## See Also

- `chezmoi/shells/` - Shell configuration files
- `chezmoi/cli/starship/` - Starship prompt configuration
