{ inputs }:
let
  fixtures = import ../fixtures/packages.nix { inherit inputs; };
  pkgs = fixtures.mkPkgs "x86_64-linux";
  home = fixtures.mkHome "x86_64-linux" [
    ../../home/common.nix
    ../../modules/editors/nvim
  ];
  selectedNodejs = builtins.head (
    builtins.filter (package: (package.pname or null) == "nodejs") home.config.home.packages
  );
in
{
  testNodejsModuleSelectionUsesCurrentNixpkgsNodejs24 = {
    expr = selectedNodejs.drvPath;
    expected = pkgs.nodejs_24.drvPath;
  };
}
