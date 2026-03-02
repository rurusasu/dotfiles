# AGENTS

Purpose: System-level NixOS host profiles.
Expected contents:

- default.nix: imports all host profile modules.
- fonts/: system font configuration.
- k3s/: Kubernetes (k3s) with Cilium CNI configuration (GKE validation environment).
  Notes:
- These are NixOS module options (not Home Manager).
- Imported by hosts in nix/hosts/.
