{ inputs }:
let
  fixtures = import ../fixtures/packages.nix { inherit inputs; };
in
{
  testDevcontainerUsesTheSharedUnixHomeManagerModule = {
    expr =
      map
        (
          system:
          builtins.elem (fixtures.mkPkgs system).devcontainer
            (fixtures.mkHome system [
              (import ../../default.nix { }).homeModules.common
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
      true
      true
    ];
  };
}
