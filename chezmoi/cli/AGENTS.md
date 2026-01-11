# CLI Tool Configurations

Configuration files for command-line tools.

## Tools

| Tool | Config Path | Deployed To | Description |
|------|-------------|-------------|-------------|
| fd | `fd/ignore` | `~/.config/fd/ignore` | File finder ignore patterns |
| ripgrep | `ripgrep/config` | `~/.config/ripgrep/config` | Search tool options |
| starship | `starship/starship.toml` | `~/.config/starship.toml` | Prompt configuration |
| ghq | `ghq/config` | `~/.config/ghq/config` | Git repository manager |
| zoxide | `zoxide/env` | (reference) | Directory jumper env vars |

## Installation

Tools are installed via:
- **Linux/WSL**: Nix Home Manager (`home.packages`)
- **Windows**: winget or scoop

## Tool Details

### fd
Fast file finder. Ignore patterns exclude:
- `.git/`, `node_modules/`, `target/`, `__pycache__/`
- Build directories, package caches
- WSL system paths

### ripgrep
Fast search tool. Options:
- Smart-case matching
- Hidden files included
- `.git/` excluded

### starship
Cross-shell prompt. Shows:
- OS symbol, username, hostname
- Directory (git-aware truncation)
- Git branch and status
- Nix shell indicator

### ghq
Git repository manager. Configured for:
- Root directory: `~/ghq`
- SSH protocol for GitHub

### zoxide
Smarter `cd` command. Environment:
- Excludes WSL system directories
- Shell integration via Nix (not this file)

## Shell Integration Note

fzf and zoxide shell integrations are managed by **Nix Home Manager**, which injects initialization code into shell configs automatically.
