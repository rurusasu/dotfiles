# ripgrep Configuration

ripgrep (rg) is a fast line-oriented search tool.

## Files

| File | Deployed To |
|------|-------------|
| `config` | `~/.config/ripgrep/config` |

## Configuration

Current settings:
- `--smart-case`: Case-insensitive unless uppercase is used
- `--hidden`: Include hidden files
- `--glob=!.git/*`: Exclude .git directory

## Installation

- **Linux/WSL**: `nix` (home.packages)
- **Windows**: `winget install BurntSushi.ripgrep.MSVC`

## Usage

```bash
# Search pattern
rg pattern

# Search in specific file types
rg -t py pattern

# Search with context
rg -C 3 pattern
```

## Environment Variable

ripgrep reads config from `RIPGREP_CONFIG_PATH`. The deployment places config in the standard XDG location.
