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

  testArcUsesAppxLaunchTargetVerifier = {
    expr = windows."TheBrowserCompany.Arc".verifyCommand;
    expected = {
      type = "appxLaunchTarget";
      command = "TheBrowserCompany.Arc";
      args = [ "TheBrowserCompany.Arc_ttt1ap7aakyb4!Arc" ];
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
