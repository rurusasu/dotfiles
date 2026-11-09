{ homeConfigurations }:
let
  installed =
    home: builtins.any (package: (package.pname or "") == "chatgpt") home.config.home.packages;
in
{
  testChatGPTDesktopKeepsTheAppProvidedCodexAcrossPlatforms = {
    expr = builtins.all (
      home:
      let
        upstream = home.pkgs.chatgpt.override { codex = null; };
      in
      home.config.programs.chatgpt.package.drvPath == upstream.drvPath
    ) (homeConfigurations.homes ++ [ homeConfigurations.linuxArm ]);
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
