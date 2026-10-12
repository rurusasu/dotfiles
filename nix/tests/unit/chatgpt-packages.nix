{ inputs }:
let
  fixtures = import ../fixtures/packages.nix { inherit inputs; };
  installed =
    system:
    builtins.any (package: (package.pname or "") == "chatgpt")
      (fixtures.mkHome system [
        ../../home/common.nix
        ../../modules/editors/nvim
      ]).config.home.packages;
in
{
  testLinuxChatGPTDesktopKeepsTheAppProvidedCodex = {
    expr =
      builtins.all
        (
          system:
          let
            modulePkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs system;
            packages = import ../../modules/ai_agents/chatgpt/packages.nix {
              inherit inputs;
              pkgs = modulePkgs;
            };
            upstream = import inputs.chatgpt-nixpkgs {
              inherit system;
              config.allowUnfree = true;
            };
          in
          packages.chatgpt.drvPath == (upstream.chatgpt.override { codex = null; }).drvPath
        )
        [
          "x86_64-linux"
          "aarch64-linux"
        ];
    expected = true;
  };

  testChatGPTInstallationIsOwnedByTools = {
    expr = {
      darwin = installed "aarch64-darwin";
      linux = installed "x86_64-linux";
    };
    expected = {
      darwin = true;
      linux = false;
    };
  };
}
