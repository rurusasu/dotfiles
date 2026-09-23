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
  isClaudeOrTablePlus = value:
    builtins.match ".*(claude|tableplus).*" (pkgs.lib.toLower value) != null;
  matchingNames = attrs: builtins.filter isClaudeOrTablePlus (builtins.attrNames attrs);
  matchingMappingEntries = attrs:
    builtins.filter isClaudeOrTablePlus (builtins.attrNames attrs ++ builtins.attrValues attrs);
  matchingListEntries = values: builtins.filter isClaudeOrTablePlus values;
in
{
  testClaudeAndTablePlusAreAbsentFromEvaluatedPackageCatalog = {
    expr = {
      supportReport = matchingNames sets.supportReport;
      winget = matchingMappingEntries sets.wingetMap;
      msstore = matchingMappingEntries sets.msstoreMap;
      npm = matchingMappingEntries sets.npmMap;
      pnpmGlobal = matchingListEntries sets.pnpmGlobal;
      windowsOnly = {
        winget = matchingListEntries sets.windowsOnly.winget;
        msstore = matchingListEntries sets.windowsOnly.msstore;
        npm = matchingListEntries sets.windowsOnly.npm;
        pnpm = matchingListEntries sets.windowsOnly.pnpm;
      };
    };
    expected = {
      supportReport = [ ];
      winget = [ ];
      msstore = [ ];
      npm = [ ];
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
