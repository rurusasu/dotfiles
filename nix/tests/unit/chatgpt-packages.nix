{ inputs }:
let
  installed =
    system:
    builtins.any (package: (package.pname or "") == "chatgpt")
      ((import ../fixtures/packages.nix { inherit inputs; }).mkHome system [
        (
          if system == "aarch64-darwin" then
            (import ../../default.nix { }).homeModules.darwin
          else
            (import ../../default.nix { }).homeModules.common
        )
        ../../modules/editors/nvim
      ]).config.home.packages;
in
{
  testChatGPTDesktopKeepsTheAppProvidedCodexAcrossPlatforms = {
    expr =
      builtins.all
        (
          system:
          let
            modulePkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs system;
          in
          ((import ../../modules/ai_agents/chatgpt).packages {
            pkgs = modulePkgs;
          }).chatgpt.drvPath == (modulePkgs.chatgpt.override { codex = null; }).drvPath
        )
        [
          "x86_64-linux"
          "aarch64-linux"
          "aarch64-darwin"
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
