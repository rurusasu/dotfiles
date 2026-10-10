{ inputs }:
let
  pkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs "aarch64-darwin";
  sets = import ../../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
in
{
  testCodexCatalogDoesNotInjectAHostPackage = {
    expr = {
      selected = builtins.elem pkgs.hello sets.all;
      catalogEntry = sets.supportReport ? codex;
    };
    expected = {
      selected = false;
      catalogEntry = false;
    };
  };
}
