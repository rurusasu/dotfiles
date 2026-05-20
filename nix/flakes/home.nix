# Standalone Home Manager configurations for non-NixOS systems.
# Usage:
#   home-manager switch --flake .#aarch64-darwin
#   home-manager switch --flake .#x86_64-darwin
#   home-manager switch --flake .#x86_64-linux
#   home-manager switch --flake .#aarch64-linux
{ inputs, ... }:
let
  workmuxOverlay = final: prev: {
    workmux = inputs.workmux.packages.${prev.stdenv.hostPlatform.system}.default;
  };
  mkHome =
    system:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ workmuxOverlay ];
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
