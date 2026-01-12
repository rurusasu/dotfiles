# AGENTS

Purpose: Nix configuration root for this repo.

## Architecture

- **No Home Manager** - Packages installed via `nix profile`, dotfiles managed by chezmoi
- NixOS-WSL for system configuration
- Flakes with flake-parts for composition

## Expected contents

- `flake.nix` lives at repo root (not here); this tree is referenced by flake modules
- `nix/flakes/` - flake-parts composition and outputs wiring
- `nix/hosts/<host>/` - per-host NixOS system configs
- `nix/modules/` - reusable modules (host and wsl)
- `nix/packages/` - package sets for `nix profile install`
- `nix/profiles/` - shared feature bundles for hosts
- `nix/overlays/` - nixpkgs overlays (if any)
- `nix/templates/` - project templates for `nix flake init`
- `nix/lib/` - utility functions

## Usage

```bash
# Install packages (any system with Nix + flakes)
nix profile install .#default

# Rebuild NixOS-WSL
sudo nixos-rebuild switch --flake .#nixos
```

## Notes

- User dotfiles are managed by chezmoi (repo root `chezmoi/`)
- `windows/install-nixos-wsl.ps1` requires admin elevation
