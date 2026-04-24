# Standalone Home Manager configurations for non-NixOS systems.
# Usage:
#   home-manager switch --flake .#aarch64-darwin
#   home-manager switch --flake .#x86_64-darwin
#   home-manager switch --flake .#x86_64-linux
#   home-manager switch --flake .#aarch64-linux
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
