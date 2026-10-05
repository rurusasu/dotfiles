{
  inputs,
  withSystem,
  ...
}:
let
  Hosts = import ./lib/hosts.nix { inherit inputs; };
  hostSpecs = Hosts.mkNixosHostSpecs { };
in
{
  flake = {
    nixosConfigurations = {
      nixos =
        let
          inherit (hostSpecs.nixos) system;
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
            inherit (hostSpecs.nixos) hostPath homeModulePath;
            extraModules = [
              inputs.nixos-wsl.nixosModules.wsl
            ];
          }
        );

    }
    // inputs.nixpkgs.lib.optionalAttrs (hostSpecs ? linux) {
      linux =
        let
          hostSpec = hostSpecs.linux;
          inherit (hostSpec) system;
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
            inherit (hostSpec) hostPath homeModulePath;
            extraModules = [ (/. + hostSpec.hardwareConfig) ];
          }
        );
    };
  };
}
