{ inputs }:
let
  system = "aarch64-darwin";
  pkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs system;
  sets = import ../../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
    catalogOverride = {
      gui = {
        pkg = pkgs.hello;
        category = "test";
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
  catalogSets = import ../../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
  customFallbackSets = import ../../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    catalogOverride = import ../../packages/catalog/desktop.nix (
      (import ../../packages/catalog/context.nix { inherit pkgs; })
      // {
        inherit pkgs;
        inherit (pkgs) lib;
        selectDarwinPackage = _: customPackage: customPackage;
        darwinProviderCandidate = _: {
          source = "custom";
          nixAttr = null;
        };
      }
    );
  };
  contains = package: packages: builtins.elem package packages;
  defaultSystem = sets.darwinSystemPackages;
  defaultHome = sets.darwinHomePackages;
  promotedDarwinGuiPackages = {
    diaBrowser = pkgs.callPackage ../../packages/dia-browser { };
  };
  containsDerivation =
    expected: packages: builtins.any (package: package.drvPath == expected.drvPath) packages;
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
    };
    expected = {
      default = {
        guiSystem = true;
        guiHome = false;
        commandSystem = false;
        commandHome = true;
      };
    };
  };

  testDarwinGuiPromotionsSelectTheirCustomSystemDerivations = {
    expr = builtins.mapAttrs (_: package: {
      system = containsDerivation package catalogSets.darwinSystemPackages;
      home = containsDerivation package catalogSets.darwinHomePackages;
    }) promotedDarwinGuiPackages;
    expected = {
      diaBrowser = {
        system = true;
        home = false;
      };
    };
  };

  testRaycastCatalogDerivationIsSelectedForDarwinSystem = {
    expr = containsDerivation pkgs.raycast catalogSets.darwinSystemPackages;
    expected = true;
  };

  testDarwinCustomProviderFallbacksResolveVendorDerivations = {
    expr = map (package: package.drvPath) (
      customFallbackSets.resolve [
        "dia-browser"
      ]
    );
    expected = [
      promotedDarwinGuiPackages.diaBrowser.drvPath
    ];
  };

  testDarwinTerminalGuiPackagesUseNativeWindowManagerAndTerminals = {
    expr = builtins.sort builtins.lessThan (
      map (package: package.pname) (
        builtins.filter (
          package: containsDerivation package catalogSets.terminal
        ) catalogSets.darwinSystemPackages
      )
    );
    expected = [
      "aerospace"
    ];
  };
}
