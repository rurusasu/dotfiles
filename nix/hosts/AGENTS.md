# AGENTS

Purpose
Purpose: per-host system definitions (NixOS).
Expected contents:
- <host>/default.nix: imports modules and configuration.nix.
- <host>/configuration.nix: host-specific system config (copy from /etc/nixos when applicable).
- <host>/hardware-configuration.nix: hardware config (NixOS only).

