{ fixtures }:
{
  testDiscordPreservesWindowsDistribution = {
    expr = fixtures.windowsPackages."Discord.Discord".verifyCommand;
    expected = {
      command = "Discord";
      type = "windowsInstalledProduct";
      uninstallEntry = {
        displayName = "Discord";
        executablePaths = [ "%LOCALAPPDATA%\\Discord\\app-*\\Discord.exe" ];
        productCodes = [ "Discord" ];
        publisher = "Discord Inc.";
      };
    };
  };
}
