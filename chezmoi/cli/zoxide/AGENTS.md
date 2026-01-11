# zoxide Configuration

zoxide is a smarter `cd` command that learns your habits.

## Files

| File | Purpose |
|------|---------|
| `env` | Environment variables (reference) |

## Environment Variables

- `_ZO_EXCLUDE_DIRS`: Directories to exclude from database
  - `/mnt/wsl/*`: WSL system mount
  - `/mnt/wslg/*`: WSL graphics mount

## Shell Integration

Shell integration is managed by **Nix Home Manager**, not this file:
```nix
programs.zoxide = {
  enable = true;
  enableBashIntegration = true;
  enableZshIntegration = true;
  options = [ "--cmd cd" ];
};
```

This replaces `cd` with `z` functionality.

## Installation

- **Linux/WSL**: `nix` (programs.zoxide)
- **Windows**: `winget install ajeetdsouza.zoxide`

## Usage

```bash
# Jump to directory matching "foo"
cd foo

# Interactive selection
cdi

# Add directory to database
zoxide add /path/to/dir
```

## Database

zoxide maintains a database of frequently visited directories at `~/.local/share/zoxide/db.zo`.
