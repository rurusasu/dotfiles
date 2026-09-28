{ inputs }:
let
  pkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs "aarch64-darwin";
  inherit (pkgs) lib;
  merge = import ../../packages/catalog/merge.nix { inherit lib; };
  fixture = {
    pkg = pkgs.hello;
    category = "fixture";
    npm = "fixture-cli";
  };
  sets = import ../../packages/sets.nix {
    inherit pkgs lib;
    catalogOverride = {
      base = fixture;
      optional = fixture // {
        installFeature = "FixtureFeature";
      };
    };
  };
in
{
  testPackageCatalogMergesDisjointOwners = {
    expr = merge {
      core.alpha.category = "core";
      dev.beta.category = "dev";
    };
    expected = {
      alpha.category = "core";
      beta.category = "dev";
    };
  };

  testPackageCatalogRejectsDuplicateOwners = {
    expr =
      (builtins.tryEval (merge {
        core.shared.category = "core";
        dev.shared.category = "dev";
      })).success;
    expected = false;
  };

  testPackageCatalogRejectsMisplacedCategory = {
    expr =
      (builtins.tryEval (merge {
        core.misplaced.category = "dev";
      })).success;
    expected = false;
  };

  testPackageCatalogOverrideRemainsIsolated = {
    expr = {
      catalogIds = builtins.filter (name: !(builtins.hasAttr name sets.windowsOnlySupport)) (
        builtins.attrNames sets.supportReport
      );
      inherit (sets) npmMap wingetMap providerErrors;
      baseProvider = sets.supportReport.base.windows;
    };
    expected = {
      catalogIds = [
        "base"
        "optional"
      ];
      npmMap = {
        base = "fixture-cli";
        optional = "fixture-cli";
      };
      wingetMap = { };
      providerErrors = [ ];
      baseProvider = {
        provider = "npm";
        source = "npm";
        identity = "fixture-cli";
      };
    };
  };

  testPackageCatalogOverridePreservesFeatureSelection = {
    expr = lib.mapAttrs (_: packages: map (package: package.drvPath) packages) {
      category = sets.fixture;
      inherit (sets) all;
      defaultFeatures = sets.allForInstallFeatures [ ];
      enabledFeatures = sets.allForInstallFeatures [ "FixtureFeature" ];
      excluded = sets.allWithout [ "base" ];
      excludedWithoutFeature = sets.allWithoutForInstallFeatures [ ] [ "base" ];
      explicit = sets.resolveForInstallFeatures [ ] [ "optional" "base" ];
    };
    expected =
      let
        hello = pkgs.hello.drvPath;
      in
      {
        category = [ hello ];
        all = [
          hello
          hello
        ];
        defaultFeatures = [ hello ];
        enabledFeatures = [
          hello
          hello
        ];
        excluded = [ hello ];
        excludedWithoutFeature = [ ];
        explicit = [ hello ];
      };
  };
}
