{
  inputs,
  withSystem,
  ...
}:
let
  Hosts = import ./lib/hosts.nix { inherit inputs; };
  workmuxOverlay = final: prev: {
    workmux = inputs.workmux.packages.${prev.stdenv.hostPlatform.system}.default.overrideAttrs (_: {
      doCheck = false;
    });
  };
  hardwareConfig = builtins.getEnv "DOTFILES_NIXOS_HARDWARE_CONFIG";
  requestedSystem = builtins.getEnv "DOTFILES_SYSTEM";
  nativeLinuxSystem = if requestedSystem == "" then "x86_64-linux" else requestedSystem;
in
{
  flake = {
    nixosConfigurations = {
      nixos =
        let
          system = "x86_64-linux";
        in
        withSystem system (
          { pkgs, ... }:
          let
            siteLib = import ../lib {
              inherit pkgs system;
              inherit (pkgs) lib;
            };
          in
          Hosts.mkNixos {
            inherit system siteLib;
            hostPath = ../hosts/wsl;
            homeModulePath = ../home/wsl/users.nix;
            overlays = [ workmuxOverlay ];
            extraModules = [
              inputs.nixos-wsl.nixosModules.wsl
            ];
          }
        );

    }
    // inputs.nixpkgs.lib.optionalAttrs (hardwareConfig != "") {
      linux =
        let
          system = nativeLinuxSystem;
        in
        withSystem system (
          { pkgs, ... }:
          let
            siteLib = import ../lib {
              inherit pkgs system;
              inherit (pkgs) lib;
            };
          in
          Hosts.mkNixos {
            inherit system siteLib;
            hostPath = ../hosts/linux;
            homeModulePath = ../home/linux/users.nix;
            overlays = [ workmuxOverlay ];
            extraModules = [ (/. + hardwareConfig) ];
          }
        );
    };
  };
}
