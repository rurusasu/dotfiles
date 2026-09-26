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
  testCodexCatalogDoesNotInjectAHostPackage = {
    expr = {
      selected = builtins.elem pkgs.hello sets.all;
      provider = sets.supportReport.codex.linux.provider;
    };
    expected = {
      selected = false;
      provider = "npm";
    };
  };
}
