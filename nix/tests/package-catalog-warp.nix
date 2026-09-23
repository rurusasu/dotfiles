{ inputs }:
let
  pkgs = (import ../test-fixtures.nix { inherit inputs; }).mkPkgs "aarch64-darwin";
  sets = import ../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
in
{
  testWarpIsAbsentFromEvaluatedPackageCatalog = {
    expr = {
      catalogEntry = builtins.hasAttr "warp-terminal" sets.supportReport;
      wingetMapping = builtins.elem "Warp.Warp" (builtins.attrValues sets.wingetMap);
      selectedPackage = builtins.any (package: pkgs.lib.getName package == "warp-terminal") sets.all;
    };
    expected = {
      catalogEntry = false;
      wingetMapping = false;
      selectedPackage = false;
    };
  };
}
