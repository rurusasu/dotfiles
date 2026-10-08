{
  windowsOnly = [ "Discord.Discord" ];
  windowsOnlySupport."Discord.Discord" = {
    windows = {
      provider = "winget";
      source = "winget";
      identity = "Discord.Discord";
    };
    darwin.unsupported = "Unix installation is owned by the Discord Home Manager module";
    linux.unsupported = "Unix installation is owned by the Discord Home Manager module";
  };
  wingetVerifyById."Discord.Discord" = {
    type = "windowsInstalledProduct";
    command = "Discord";
    uninstallEntry = {
      productCodes = [ "Discord" ];
      displayName = "Discord";
      publisher = "Discord Inc.";
      executablePaths = [ "%LOCALAPPDATA%\\Discord\\app-*\\Discord.exe" ];
    };
  };
}
