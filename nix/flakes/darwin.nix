{ inputs, ... }:
let
  system = "aarch64-darwin";
  Workmux = import ./lib/workmux.nix { inherit inputs; };
  workmuxOverlay = Workmux.mkOverlay (_: inputs.workmux.packages.${system}.default);
in
{
  flake.darwinConfigurations.macos = inputs.nix-darwin.lib.darwinSystem {
    inherit system;
    specialArgs = { inherit inputs; };
    modules = [
      inputs.nix-homebrew.darwinModules.nix-homebrew
      inputs.home-manager.darwinModules.home-manager
      {
        nixpkgs.config.allowUnfree = true;
        nixpkgs.overlays = [ workmuxOverlay ];
      }
      ../darwin/default.nix
    ];
  };
}
