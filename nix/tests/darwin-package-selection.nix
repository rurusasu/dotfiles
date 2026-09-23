{ inputs }:
let
  system = "aarch64-darwin";
  pkgs = import inputs.nixpkgs {
    inherit system;
    config.allowUnfree = true;
  };
  sets = import ../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
    catalogOverride = {
      gui = {
        pkg = pkgs.hello;
        category = "test";
        installFeature = "WithGui";
        support.darwin = {
          provider = "nix";
          source = "nixpkgs";
          nixAttr = "hello";
          identity.appName = "Test App.app";
        };
      };
      command = {
        pkg = pkgs.cowsay;
        category = "test";
        support.darwin = {
          provider = "nix";
          source = "nixpkgs";
          nixAttr = "cowsay";
          identity = "cowsay";
        };
      };
    };
  };
  catalogSets = import ../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
  contains = package: packages: builtins.elem package packages;
  defaultSystem = sets.darwinSystemPackagesForInstallFeatures [ ];
  defaultHome = sets.darwinHomePackagesForInstallFeatures [ ];
  enabledSystem = sets.darwinSystemPackagesForInstallFeatures [ "WithGui" ];
  enabledHome = sets.darwinHomePackagesForInstallFeatures [ "WithGui" ];
  promotedDarwinGuiPackages = {
    hammerspoon = pkgs.callPackage ../packages/hammerspoon { };
    diaBrowser = pkgs.callPackage ../packages/dia-browser { };
    orcaEditor = pkgs.callPackage ../packages/orca-editor { };
  };
  containsDerivation = expected: packages:
    builtins.any (package: package.drvPath == expected.drvPath) packages;
in
{
  testDarwinGuiPackagesUseSystemSetAndCommandsUseHomeManager = {
    expr = {
      default = {
        guiSystem = contains pkgs.hello defaultSystem;
        guiHome = contains pkgs.hello defaultHome;
        commandSystem = contains pkgs.cowsay defaultSystem;
        commandHome = contains pkgs.cowsay defaultHome;
      };
      enabled = {
        guiSystem = contains pkgs.hello enabledSystem;
        guiHome = contains pkgs.hello enabledHome;
        commandSystem = contains pkgs.cowsay enabledSystem;
        commandHome = contains pkgs.cowsay enabledHome;
      };
    };
    expected = {
      default = {
        guiSystem = false;
        guiHome = false;
        commandSystem = false;
        commandHome = true;
      };
      enabled = {
        guiSystem = true;
        guiHome = false;
        commandSystem = false;
        commandHome = true;
      };
    };
  };

  testDarwinGuiPromotionsSelectTheirCustomSystemDerivations = {
    expr = builtins.mapAttrs (_: package: {
      system = containsDerivation package defaultSystem;
      home = containsDerivation package defaultHome;
    }) promotedDarwinGuiPackages;
    expected = {
      hammerspoon = {
        system = true;
        home = false;
      };
      diaBrowser = {
        system = true;
        home = false;
      };
      orcaEditor = {
        system = true;
        home = false;
      };
    };
  };

  testRaycastCatalogDerivationIsSelectedForDarwinSystem = {
    expr = containsDerivation pkgs.raycast (
      catalogSets.darwinSystemPackagesForInstallFeatures [ ]
    );
    expected = true;
  };
}
