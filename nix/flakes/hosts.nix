{
  inputs,
  withSystem,
  ...
}:
let
  Hosts = import ./lib/hosts.nix { inherit inputs; };
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
            users = {
              nixos = ../home/wsl;
            };
            extraModules = [
              inputs.nixos-wsl.nixosModules.wsl
            ];
          }
        );
    };
  };
}
