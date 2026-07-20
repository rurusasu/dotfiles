{ inputs, ... }:
let
  requestedSystem = builtins.getEnv "DOTFILES_SYSTEM";
  system = if requestedSystem == "" then "x86_64-linux" else requestedSystem;
  Workmux = import ./lib/workmux.nix { inherit inputs; };
  workmuxOverlay = Workmux.mkOverlay (_: inputs.workmux.packages.${system}.default);
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
