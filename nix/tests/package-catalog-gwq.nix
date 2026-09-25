{ inputs }:
let
  pkgs = (import ../test-fixtures.nix { inherit inputs; }).mkPkgs "x86_64-linux";
  sets = import ../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
  gwq = sets.supportReport.gwq;
in
{
  testGwqUsesNixpkgsAndHasNoWindowsProvider = {
    expr = {
      selectedPackage = builtins.any (package: package.drvPath == pkgs.gwq.drvPath) sets.all;
      windows = {
        provider = gwq.windows.provider or null;
        unsupported = gwq.windows.unsupported or null;
        winget = sets.wingetMap.gwq or null;
        msstore = sets.msstoreMap.gwq or null;
        npm = sets.npmMap.gwq or null;
      };
    };
    expected = {
      selectedPackage = true;
      windows = {
        provider = null;
        unsupported = "No reviewed Windows package provider is selected";
        winget = null;
        msstore = null;
        npm = null;
      };
    };
  };
}
