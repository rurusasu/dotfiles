{ inputs, ... }:
let
  system = "aarch64-darwin";
  workmuxOverlay = _: _: {
    workmux = inputs.workmux.packages.${system}.default.overrideAttrs (_: {
      doCheck = false;
    });
  };
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
