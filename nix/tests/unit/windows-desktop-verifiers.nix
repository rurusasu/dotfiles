{ inputs }:
let
  windows = (import ../fixtures/packages.nix { inherit inputs; }).windowsPackages;
in
{
  testPowerToysUsesWinGetUninstallRegistrationIdentity = {
    expr = windows."Microsoft.PowerToys".verifyCommand.uninstallEntry;
    expected = {
      displayNamePattern = "^PowerToys(?: \\(Preview\\))?$";
      publisher = "Microsoft Corporation";
      executablePaths = [
        "%ProgramFiles%\\PowerToys\\PowerToys.exe"
        "%LOCALAPPDATA%\\PowerToys\\PowerToys.exe"
      ];
    };
  };

  testWindowsOnePasswordRemainsInstallableForWslInterop = {
    expr = windows."AgileBits.1Password".verifyCommand;
    expected = {
      type = "windowsInstalledProduct";
      command = "AgileBits.1Password";
      appxPackage = {
        executable = "1Password.exe";
        name = "AgileBits.1Password";
        packageFamilyName = "Agilebits.1Password_amwd9z03whsfe";
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

  testWindowsTerminalUsesAppxLaunchTargetVerifier = {
    expr = windows."Microsoft.WindowsTerminal".verifyCommand;
    expected = {
      type = "appxLaunchTarget";
      command = "Microsoft.WindowsTerminal";
      args = [ "Microsoft.WindowsTerminal_8wekyb3d8bbwe!App" ];
    };
  };
}
