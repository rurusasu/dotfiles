{ inputs }:
let
  system = "aarch64-darwin";
  pkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs system;
  codexPackage = pkgs.hello;
  sets = import ../../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    inherit codexPackage;
  };
in
{
  testTartCatalogUsesResolvedNixPackageAndIdentity = {
    expr = {
      resolvedPackage = sets.darwinPackages.tart.drvPath;
      provider = sets.supportReport.tart.darwin.provider;
      source = sets.supportReport.tart.darwin.source;
      nixAttr = sets.supportReport.tart.darwin.nixAttr;
      identity = sets.supportReport.tart.darwin.identity;
    };
    expected = {
      resolvedPackage = pkgs.tart.drvPath;
      provider = "nix";
      source = "nixpkgs";
      nixAttr = "tart";
      identity = "tart";
    };
  };
}
