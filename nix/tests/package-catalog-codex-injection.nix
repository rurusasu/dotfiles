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
in
{
  testCodexCatalogIncludesInjectedPackage = {
    expr = builtins.elem pkgs.hello sets.llm;
    expected = true;
  };
}
