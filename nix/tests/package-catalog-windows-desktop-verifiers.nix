{ inputs }:
let
  pkgs = (import ../test-fixtures.nix { inherit inputs; }).mkPkgs "aarch64-darwin";
  sets = import ../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
in
{
  testPowerToysUsesWinGetUninstallRegistrationIdentity = {
    expr = sets.wingetVerifyById."Microsoft.PowerToys".uninstallEntry;
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
    expr = sets.wingetVerifyById."TheBrowserCompany.Arc";
    expected = {
      type = "appxLaunchTarget";
      command = "TheBrowserCompany.Arc";
      args = [ "TheBrowserCompany.Arc_ttt1ap7aakyb4!Arc" ];
    };
  };

  testWindowsTerminalUsesAppxLaunchTargetVerifier = {
    expr = sets.wingetVerifyById."Microsoft.WindowsTerminal";
    expected = {
      type = "appxLaunchTarget";
      command = "Microsoft.WindowsTerminal";
      args = [ "Microsoft.WindowsTerminal_8wekyb3d8bbwe!App" ];
    };
  };
}
