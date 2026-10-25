{ inputs }:
let
  fixtures = import ./packages.nix { inherit inputs; };
  inherit (fixtures) mkPkgs;

  testHome = {
    username = "test-user";
    homeDirectory = "/home/test-user";
    stateVersion = "25.05";
  };

  mkHome =
    {
      system,
      module,
      specialArgs ? { },
    }:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = mkPkgs system;
      extraSpecialArgs = {
        inherit inputs;
      }
      // specialArgs;
      modules = [
        (_: { home = testHome; })
        module
      ];
    };

  linux = mkHome {
    system = "x86_64-linux";
    module = fixtures.homeModule "linux";
  };

  wsl = mkHome {
    system = "x86_64-linux";
    module = fixtures.homeModule "wsl";
  };

  darwin = mkHome {
    system = "aarch64-darwin";
    module = fixtures.homeModule "darwin";
  };

in
{
  inherit
    mkHome
    mkPkgs
    testHome
    linux
    wsl
    darwin
    ;
  linuxArm = mkHome {
    system = "aarch64-linux";
    module = fixtures.homeModule "linux";
  };
  configuredChrome = home: (import ../../modules/browsers/chrome).package { inherit (home) pkgs; };
  common = mkHome {
    system = "x86_64-linux";
    module = fixtures.homeModule "common";
  };
  homes = [
    linux
    wsl
    darwin
  ];
  lib = inputs.nixpkgs.lib;
}
