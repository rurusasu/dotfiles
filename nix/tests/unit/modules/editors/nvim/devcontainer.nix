{ fixtures }:

{
  testDevcontainerUsesTheSharedUnixHomeManagerModule = {
    expr =
      map
        (
          system:
          builtins.elem (fixtures.mkPkgs system).devcontainer
            (fixtures.mkHome system [
              (fixtures.homeModule "common")
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
