# Standalone homeConfigurations Design

## Problem

Home Manager is only integrated as a NixOS module, so it cannot be used on non-NixOS Linux or macOS. The WSL user config has hardcoded username/home directory, and there are no `homeConfigurations` flake outputs.

## Solution

1. Extract a shared `common.nix` that uses `builtins.getEnv` for user info (no hardcoded usernames)
2. Add `homeConfigurations` flake outputs for all 4 platforms
3. Refactor WSL `users.nix` to reuse `common.nix`

## Design

### `nix/home/common.nix` (new)

Shared Home Manager module. Uses `builtins.getEnv` to get username and home directory at build time, so no user-specific data is committed to the repo.

```nix
{ pkgs, lib, ... }:
let
  sets = import ../packages/sets.nix { inherit pkgs lib; };
  user = builtins.getEnv "USER";
  home = builtins.getEnv "HOME";
in
{
  home.username = if user != "" then user else "unknown";
  home.homeDirectory = if home != "" then home else "/home/unknown";
  home.stateVersion = "25.05";
  home.packages = sets.all;
  programs.home-manager.enable = true;
}
```

### `nix/home/wsl/users.nix` (modified)

Simplified to import `common.nix`:

```nix
{
  nixos = { ... }: {
    imports = [ ../common.nix ];
  };
}
```

Note: The key `nixos` refers to the NixOS system user, not a username in common.nix. This mapping is used by `home-manager.users` in the NixOS module integration.

### `nix/home/packages.nix` (deleted)

Functionality moved into `common.nix`. No longer needed as a separate file.

### `nix/flakes/home.nix` (new)

```nix
{ inputs, ... }:
let
  mkHome =
    system:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      modules = [ ../home/common.nix ];
    };
in
{
  flake.homeConfigurations = {
    "aarch64-darwin" = mkHome "aarch64-darwin";
    "x86_64-darwin" = mkHome "x86_64-darwin";
    "x86_64-linux" = mkHome "x86_64-linux";
    "aarch64-linux" = mkHome "aarch64-linux";
  };
}
```

### `nix/flakes/default.nix` (modified)

Add `./home.nix` to imports.

### Usage

```bash
# macOS (Apple Silicon)
home-manager switch --flake .#aarch64-darwin

# macOS (Intel)
home-manager switch --flake .#x86_64-darwin

# Non-NixOS Linux
home-manager switch --flake .#x86_64-linux

# WSL (existing NixOS module path still works)
sudo nixos-rebuild switch --flake .#nixos
```

## Invariants

1. No usernames or home directories hardcoded in the repository
2. `common.nix` is the single module shared by both NixOS integration and standalone
3. `builtins.getEnv` returns empty string in pure eval (`nix flake check`), but `homeConfigurations` are not checked by `nix flake check`
4. Platform guards from LIF-91 (`meta.platforms` filter) automatically apply

## Out of scope

- nix-darwin integration (LIF-92 is standalone Home Manager only)
- Windows package manager strategy (separate issue)
