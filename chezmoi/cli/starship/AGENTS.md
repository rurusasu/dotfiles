# Starship Configuration

Starship is a fast, customizable cross-shell prompt.

## Files

| File | Deployed To |
|------|-------------|
| `starship.toml` | `~/.config/starship.toml` |

## Prompt Elements

The prompt displays:
- OS symbol
- Username and hostname
- Memory usage
- Current directory (truncated, git-aware)
- Git branch and status
- Nix shell indicator
- Command success/failure indicator

## Git Status Symbols

| Symbol | Meaning |
|--------|---------|
| `+` | Staged changes |
| `!` | Modified files |
| `?` | Untracked files |
| `×` | Deleted files |

## Installation

- **Linux/WSL**: `nix` (home.packages)
- **Windows**: `winget install Starship.Starship`

## Shell Integration

Add to shell config (handled by Nix or manually):
```bash
eval "$(starship init bash)"  # or zsh
```

## Customization

Edit `starship.toml` to customize. See [Starship docs](https://starship.rs/config/).
