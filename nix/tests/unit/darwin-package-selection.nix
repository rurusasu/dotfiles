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
  defaultSystem = sets.darwinSystemPackagesForInstallFeatures [ ];
  defaultHome = sets.darwinHomePackagesForInstallFeatures [ ];
  enabledSystem = sets.darwinSystemPackagesForInstallFeatures [ "WithGui" ];
  enabledHome = sets.darwinHomePackagesForInstallFeatures [ "WithGui" ];
  promotedDarwinGuiPackages = {
    diaBrowser = pkgs.callPackage ../../packages/dia-browser { };
    orcaEditor = pkgs.callPackage ../../packages/orca-editor { };
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
      system = containsDerivation package (catalogSets.darwinSystemPackagesForInstallFeatures [ ]);
      home = containsDerivation package (catalogSets.darwinHomePackagesForInstallFeatures [ ]);
    }) promotedDarwinGuiPackages;
    expected = {
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
    expr = containsDerivation pkgs.raycast (catalogSets.darwinSystemPackagesForInstallFeatures [ ]);
    expected = true;
  };

  testDarwinCustomProviderFallbacksResolveVendorDerivations = {
    expr = map (package: package.drvPath) (
      customFallbackSets.resolveForInstallFeatures
        [ ]
        [
          "dia-browser"
          "orca-editor"
        ]
    );
    expected = [
      promotedDarwinGuiPackages.diaBrowser.drvPath
      promotedDarwinGuiPackages.orcaEditor.drvPath
    ];
  };

  testDarwinTerminalGuiPackagesUseNativeWindowManagerAndTerminals = {
    expr = builtins.sort builtins.lessThan (
      map (package: package.pname) (
        builtins.filter (package: containsDerivation package catalogSets.terminal) (
          catalogSets.darwinSystemPackagesForInstallFeatures [ ]
        )
      )
    );
    expected = [
      "aerospace"
      "ghostty-bin"
      "wezterm"
    ];
  };
}
