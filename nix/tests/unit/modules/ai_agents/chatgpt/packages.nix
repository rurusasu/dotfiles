{
  fixtures,
  homeConfigurations,
  code,
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
            modulePkgs = fixtures.mkPkgs system;
          in
          (code.nix.modules.ai_agents.chatgpt.package {
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
