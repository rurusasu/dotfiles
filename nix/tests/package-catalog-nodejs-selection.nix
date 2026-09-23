{ inputs }:
let
  system = "x86_64-linux";
  pkgs = import inputs.nixpkgs {
    inherit system;
    config.allowUnfree = true;
  };
  sets = import ../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
  selectedNodejs = builtins.head (
    builtins.filter (package: (package.pname or null) == "nodejs") sets.dev
  );
in
{
  testNodejsCatalogSelectionUsesCurrentNixpkgsNodejs24 = {
    expr = selectedNodejs.drvPath;
    expected = pkgs.nodejs_24.drvPath;
  };
}
