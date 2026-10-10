{ inputs }:
let
  system = "aarch64-darwin";
  pkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs system;
  sets = import ../../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
in
{
  testCodexCliIsNotIndependentlyInstalled = {
    expr = {
      catalogEntry = sets.supportReport ? codex;
      npmMapping = sets.npmMap ? codex;
      nixPackageSelected = builtins.elem pkgs.hello sets.all;
    };
    expected = {
      catalogEntry = false;
      npmMapping = false;
      nixPackageSelected = false;
    };
  };
}
