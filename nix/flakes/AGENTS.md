# AGENTS

Purpose: flake-parts entrypoint and composition for outputs.
Expected contents:
- default.nix: flake-parts config (imports, perSystem, flake outputs).
- hosts.nix: nixosConfigurations wiring.
- systems.nix: supported systems list.
- treefmt.nix: treefmt integration.
- lib/: helper functions used by flake-parts.
Notes:
- Keep outputs small; push logic into nix/hosts, nix/modules, nix/profiles.
- nixosConfigurations attribute name should match networking.hostName for auto-detection.
- Current host: `nixos` (WSL)
