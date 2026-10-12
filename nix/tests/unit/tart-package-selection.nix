{ inputs }:
let
  fixtures = import ../fixtures/packages.nix { inherit inputs; };
in
{
  testTartModuleIsRestrictedToDarwin = {
    expr =
      map
        (
          system:
          let
            home = fixtures.mkHome system [
              ../../home/common.nix
              ../../modules/editors/nvim
            ];
          in
          builtins.any (package: (package.pname or "") == "tart") home.config.home.packages
        )
        [
          "aarch64-darwin"
          "x86_64-linux"
          "aarch64-linux"
        ];
    expected = [
      true
      false
      false
    ];
  };
}
