{ inputs }:
let
  fixtures = import ../../../../fixtures/packages.nix { inherit inputs; };
in
{
  testDevcontainerUsesTheSharedUnixHomeManagerModule = {
    expr =
      map
        (
          system:
          builtins.elem (fixtures.mkPkgs system).devcontainer
            (fixtures.mkHome system [
              (fixtures.homeModule "common")
              ../../../../../modules/editors/nvim/home-manager.nix
              ../../../../../modules/editors/nvim/plugins.home-manager.nix
              ../../../../../modules/editors/nvim/runtime.home-manager.nix
              { programs.neovim.enable = true; }
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
