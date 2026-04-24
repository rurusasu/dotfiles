# Shared Home Manager module for all platforms.
# Uses builtins.getEnv to avoid hardcoding usernames in the repository.
#
# Used by:
#   - nix/home/wsl/users.nix   → NixOS module integration
#   - nix/flakes/home.nix      → standalone homeConfigurations
{
  pkgs,
  lib,
  ...
}:
let
  sets = import ../packages/sets.nix { inherit pkgs lib; };
  user = builtins.getEnv "USER";
  home = builtins.getEnv "HOME";
in
{
  home.username = lib.mkDefault (if user != "" then user else "unknown");
  home.homeDirectory = lib.mkDefault (if home != "" then home else "/home/unknown");
  home.stateVersion = "25.05";
  home.packages = sets.all;
  programs.home-manager.enable = true;
}
