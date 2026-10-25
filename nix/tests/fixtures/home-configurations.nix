{ inputs }:
let
  fixtures = import ./packages.nix { inherit inputs; };
  mkPkgs = system: fixtures.mkPkgs system;
  configuredChrome = home: import ../../modules/browsers/chrome { inherit (home) pkgs; };

  testHome = {
    username = "test-user";
    homeDirectory = "/home/test-user";
    stateVersion = "25.05";
  };
  baseModule = _: { home = testHome; };

  mkHome =
    {
      system,
      module,
      specialArgs ? { },
    }:
    let
      pkgs = mkPkgs system;
    in
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inherit inputs;
      }
      // specialArgs;
      modules = [
        baseModule
        module
      ]
      ++ ((import (
        if pkgs.stdenv.hostPlatform.isDarwin then
          ../../hosts/aarch64-darwin/platform.nix
        else
          ../../hosts/shared/nixos/platform.nix
      ) { inherit pkgs inputs; }).home-manager.sharedModules or [ ]
      )
      ++ [
        ../../modules/terminals/ghostty/defaults.nix
        ../../modules/terminals/wezterm/defaults.nix
      ];
    };

  common = mkHome {
    system = "x86_64-linux";
    module = ../../home/common.nix;
  };

  linux = mkHome {
    system = "x86_64-linux";
    module = ../../hosts/shared/linux-home.nix;
  };

  wsl = mkHome {
    system = "x86_64-linux";
    module = ../../hosts/x86_64-linux/wsl/home.nix;
  };

  wslDeclarations = import ../../hosts/x86_64-linux/wsl/home.nix {
    inherit inputs;
    inherit (wsl) pkgs;
    inherit (wsl.pkgs) lib;
    inherit (common) config;
  };

  darwin = mkHome {
    system = "aarch64-darwin";
    module = ../../hosts/aarch64-darwin/home.nix;
  };

  darwinPackages = {
    pkgs = mkPkgs "aarch64-darwin";
    system = fixtures.darwin.config.environment.systemPackages;
    contains =
      package: packages: builtins.any (candidate: candidate.drvPath == package.drvPath) packages;
  };
in
{
  inherit
    mkHome
    mkPkgs
    testHome
    common
    linux
    wsl
    wslDeclarations
    darwin
    configuredChrome
    darwinPackages
    ;
  homes = [
    linux
    wsl
    darwin
  ];
  sharedConfig = common.config;
  lib = inputs.nixpkgs.lib;
}
