{
  homeConfigurations,
}:
let
  installed =
    home: builtins.any (package: (package.pname or "") == "chatgpt") home.config.home.packages;
in
{
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
