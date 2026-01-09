# AGENTS

Purpose
Purpose: Nix configuration root for this repo.
Expected contents:
- flake.nix lives at repo root (not here); this tree is referenced by flake modules.
- nix/flakes: flake-parts composition and outputs wiring.
- nix/hosts/<host>: per-host system configs.
- nix/home/<host>: per-host Home Manager entrypoints.
- nix/home/users/<user>.nix: per-user HM definitions.
- nix/home/config: source files for Home Manager-managed dotfiles.
- nix/modules: reusable modules (host and wsl).
- nix/profiles: shared feature bundles.
- nix/packages: custom packages (if any).
- nix/overlays: overlays (if any).
- nix/templates: templates/scaffolding (if any).

Notes:
- windows/install-nixos-wsl.ps1 requires admin; use elevated PowerShell or run with sudo in pwsh.
- User dotfiles are managed in repo root `chezmoi/`.
