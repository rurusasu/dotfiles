{
  inputs,
  homeConfigurations ? import ../../../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  installed =
    home: builtins.any (package: (package.pname or "") == "chatgpt") home.config.home.packages;
in
{
  testChatGPTDesktopKeepsTheAppProvidedCodexAcrossPlatforms = {
    expr =
      builtins.all
        (
          system:
          let
            modulePkgs = (import ../../../../fixtures/packages.nix { inherit inputs; }).mkPkgs system;
          in
          ((import ../../../../../modules/ai_agents/chatgpt/package.nix) {
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

  testChatGPTDesktopSelectionFollowsPlatform = {
    expr = {
      darwin = installed homeConfigurations.darwin;
      linux = installed homeConfigurations.linux;
      wsl = installed homeConfigurations.wsl;
      common = installed homeConfigurations.common;
    };
    expected = {
      darwin = true;
      linux = true;
      wsl = false;
      common = false;
    };
  };
}
