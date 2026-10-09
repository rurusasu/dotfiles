let
  cliId = "AgileBits.1Password.CLI";
  desktopId = "AgileBits.1Password";
  support = identity: {
    windows = {
      provider = "winget";
      source = "winget";
      inherit identity;
    };
    darwin.unsupported = "Unix installation is owned by the 1Password module";
    linux.unsupported = "Unix installation is owned by the 1Password module";
  };
in
{
  windowsOnly = [
    cliId
    desktopId
  ];
  windowsOnlySupport = {
    ${cliId} = support cliId;
    ${desktopId} = support desktopId;
  };
  wingetInstallArgs.${cliId} = [
    "--scope"
    "user"
  ];
  wingetPathEntries.${cliId} = [ "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\${cliId}*" ];
  wingetVerifyById = {
    ${cliId} = {
      command = "op";
      args = [ "--version" ];
    };
    ${desktopId} = {
      type = "windowsInstalledProduct";
      command = desktopId;
      appxPackage = {
        name = desktopId;
        packageFamilyName = "Agilebits.1Password_amwd9z03whsfe";
        executable = "1Password.exe";
      };
      uninstallEntry = {
        displayName = "1Password";
        executablePaths = [
          "%ProgramFiles%\\1Password\\1Password.exe"
          "%LOCALAPPDATA%\\1Password\\app\\*\\1Password.exe"
        ];
      };
    };
  };
}
