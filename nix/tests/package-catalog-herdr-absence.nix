{ inputs }:
let
  pkgs = import inputs.nixpkgs {
    system = "aarch64-darwin";
    config.allowUnfree = true;
  };
  sets = import ../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
  hasHerdr = value: builtins.match ".*herdr.*" (pkgs.lib.toLower value) != null;
  matchingNames = attrs: builtins.filter hasHerdr (builtins.attrNames attrs);
  matchingMappings = attrs: {
    catalogItems = matchingNames attrs;
    identities = builtins.filter hasHerdr (builtins.attrValues attrs);
  };
  matchingListEntries = values: builtins.filter hasHerdr values;
in
{
  testHerdrIsAbsentFromEvaluatedPackageCatalogAndProviderMappings = {
    expr = {
      supportReport = {
        catalogItems = matchingNames sets.supportReport;
        hasHerdrIdentity = builtins.match ".*Herdr\\.Herdr.*" (builtins.toJSON sets.supportReport) != null;
      };
      winget = matchingMappings sets.wingetMap;
      msstore = matchingMappings sets.msstoreMap;
      npm = matchingMappings sets.npmMap;
      pnpmGlobal = matchingListEntries sets.pnpmGlobal;
      windowsOnly = {
        winget = matchingListEntries sets.windowsOnly.winget;
        msstore = matchingListEntries sets.windowsOnly.msstore;
        npm = matchingListEntries sets.windowsOnly.npm;
        pnpm = matchingListEntries sets.windowsOnly.pnpm;
      };
    };
    expected = {
      supportReport = {
        catalogItems = [ ];
        hasHerdrIdentity = false;
      };
      winget = {
        catalogItems = [ ];
        identities = [ ];
      };
      msstore = {
        catalogItems = [ ];
        identities = [ ];
      };
      npm = {
        catalogItems = [ ];
        identities = [ ];
      };
      pnpmGlobal = [ ];
      windowsOnly = {
        winget = [ ];
        msstore = [ ];
        npm = [ ];
        pnpm = [ ];
      };
    };
  };
}
