{ inputs }:
let
  fixtures = import ./packages.nix { inherit inputs; };
  mkPkgs = system: fixtures.mkPkgs system;

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
    module = (import ../../hosts { inherit inputs; }).linuxHome;
  };

  wsl = mkHome {
    system = "x86_64-linux";
    module = ../../home/wsl.nix;
  };

  darwin = mkHome {
    system = "aarch64-darwin";
    module = ../../home/darwin.nix;
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
  configuredChrome = home: (import ../../modules/browsers/chrome).package { inherit (home) pkgs; };
  common = mkHome {
    system = "x86_64-linux";
    module = ../../home/common.nix;
  };
  wslDeclarations = import ../../home/wsl.nix {
    inherit inputs;
    inherit (wsl) config pkgs;
    inherit (wsl.pkgs) lib;
  };
  darwinPackages = {
    pkgs = mkPkgs "aarch64-darwin";
    system = fixtures.darwin.config.environment.systemPackages;
    contains =
      package: packages: builtins.any (candidate: candidate.drvPath == package.drvPath) packages;
  };
  homes = [
    linux
    wsl
    darwin
  ];
  lib = inputs.nixpkgs.lib;
}
