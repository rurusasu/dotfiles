{ inputs }:
{
  testTartModuleIsRestrictedToDarwin = {
    expr =
      map
        (
          system:
          builtins.any (package: (package.pname or "") == "tart")
            ((import ../fixtures/packages.nix { inherit inputs; }).mkHome system [
              ../../home/common.nix
              ../../modules/editors/nvim
            ]).config.home.packages
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
