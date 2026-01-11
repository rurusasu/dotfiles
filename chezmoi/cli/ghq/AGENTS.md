# ghq Configuration

ghq is a Git repository manager.

## Files

| File | Deployed To |
|------|-------------|
| `config` | `~/.config/ghq/config` |

## Configuration

- **Root directory**: `~/ghq`
- **GitHub protocol**: SSH

## Directory Structure

Repositories are cloned to:
```
~/ghq/
└── github.com/
    └── username/
        └── repository/
```

## Installation

- **Linux/WSL**: `nix` (home.packages)
- **Windows**: `scoop install ghq` or `go install github.com/x-motemen/ghq@latest`

## Usage

```bash
# Clone repository
ghq get github.com/user/repo

# List repositories
ghq list

# Navigate to repository (with fzf)
cd $(ghq list -p | fzf)
```

## Integration

Works well with:
- fzf for fuzzy repository selection
- Git for version control
- SSH keys for authentication
