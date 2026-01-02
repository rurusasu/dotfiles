# AGENTS

Purpose
Purpose: per-host system definitions (NixOS).
Expected contents:
- <host>/default.nix: imports modules and host config.
- <host>/configuration.nix: baseline system config (copied from /etc/nixos when applicable).
- <host>/hardware-configuration.nix: hardware config (NixOS only).

