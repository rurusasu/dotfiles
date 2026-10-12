{ inputs }:
let
  windows = (import ../fixtures/packages.nix { inherit inputs; }).windowsPackages;
in
{
  testDiscordPreservesWindowsDistribution = {
    expr = windows."Discord.Discord".verifyCommand;
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
