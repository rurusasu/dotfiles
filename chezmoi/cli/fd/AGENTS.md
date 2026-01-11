# fd Configuration

fd is a fast, user-friendly alternative to `find`.

## Files

| File | Deployed To |
|------|-------------|
| `ignore` | `~/.config/fd/ignore` |

## Ignore Patterns

The ignore file excludes:
- Version control: `.git/`
- Dependencies: `node_modules/`, `bower_components/`
- Build outputs: `target/`, `build/`, `dist/`, `__pycache__/`
- Caches: `.cache/`, `.npm/`, `.cargo/`
- Nix: `.nix-profile/`, `.local/share/`
- WSL system: `/mnt/wsl/`, `/mnt/wslg/`, `/sys/`, `/lib/`

## Installation

- **Linux/WSL**: `nix` (home.packages)
- **Windows**: `winget install sharkdp.fd`

## Usage

```bash
# Find files
fd pattern

# Find directories
fd -t d pattern

# Include hidden files
fd -H pattern
```

## Integration

fd is used as the backend for fzf file finding (configured in Nix).
