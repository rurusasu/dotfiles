{ inputs, ... }:
let
  requestedSystem = builtins.getEnv "DOTFILES_SYSTEM";
  system = if requestedSystem == "" then "x86_64-linux" else requestedSystem;
  workmuxOverlay = _: _: {
    workmux = inputs.workmux.packages.${system}.default.overrideAttrs (_: {
      doCheck = false;
    });
  };
  mkConfig =
    distro:
    inputs.system-manager.lib.makeSystemConfig {
      overlays = [ workmuxOverlay ];
      specialArgs = {
        inherit inputs distro;
      };
      modules = [
        inputs.home-manager.nixosModules.home-manager
        {
          nixpkgs.hostPlatform = system;
          nixpkgs.config.allowUnfree = true;
        }
        ../system-manager/default.nix
        ../system-manager/docker.nix
      ];
    };
in
{
  flake.systemConfigs = {
    ubuntu = mkConfig "ubuntu";
    debian = mkConfig "debian";
  };
}
