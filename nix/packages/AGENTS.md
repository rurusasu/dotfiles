# AGENTS

Purpose: Package sets for nix profile install.

## Expected contents

- `default.nix` - Main package set definitions for nix profile
- `<package>/default.nix` - Custom package builds (if any)

## Usage

Install packages without Home Manager using `nix profile`:

```bash
# Enable flakes (one-time setup)
# Add to ~/.config/nix/nix.conf:
# experimental-features = nix-command flakes

# Install from this repo
nix profile install github:yourusername/dotfiles#default
nix profile install .#minimal  # local repo
nix profile install .#full

# Update packages
nix profile upgrade '.*'
```

## Available package sets

- `default` - Core + dev + terminal tools
- `minimal` - Just core CLI tools
- `full` - Everything including LLM tools and editors
- `core`, `dev`, `llm`, `terminal`, `editors` - Individual sets

## Notes

- User dotfiles (configs) are managed by chezmoi, not Nix
- Nix only handles package installation
