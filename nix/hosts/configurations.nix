inputs:
let
  hardwareConfig = /etc/nixos/hardware-configuration.nix;
in
{
  nixosConfigurations = {
    wsl = inputs.nixpkgs.lib.nixosSystem {
      specialArgs = {
        inherit inputs;
        platform = "wsl";
      };
      modules = [
        { nixpkgs.hostPlatform = "x86_64-linux"; }
        ./default.nix
      ];
    };
  }
  // inputs.nixpkgs.lib.optionalAttrs (builtins.pathExists hardwareConfig) {
    linux = inputs.nixpkgs.lib.nixosSystem {
      specialArgs = {
        inherit inputs;
        platform = "linux";
      };
      modules = [
        { nixpkgs.hostPlatform = builtins.currentSystem; }
        hardwareConfig
        ./default.nix
      ];
    };
  };
  darwinConfigurations.macos = inputs.nix-darwin.lib.darwinSystem {
    system = "aarch64-darwin";
    specialArgs = {
      inherit inputs;
      platform = "darwin";
    };
    modules = [ ./default.nix ];
  };
}
