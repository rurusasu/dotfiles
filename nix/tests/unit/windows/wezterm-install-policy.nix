{ inputs }:
let
  windows = (import ../../fixtures/packages.nix { inherit inputs; }).windowsPackages;
in
{
  testWeztermStablePackageDoesNotRequireInstallerHashOverride = {
    expr = builtins.elem "--ignore-security-hash" (windows."wez.wezterm".installArgs or [ ]);
    expected = false;
  };

  testWeztermCommonWindowsInstallRemainsInCi = {
    expr = {
      ciSkipped = windows."wez.wezterm".ciSkipInstall or false;
      pathEntries = windows."wez.wezterm".pathEntries;
      verifier = windows."wez.wezterm".verifyCommand;
    };
    expected = {
      ciSkipped = false;
      pathEntries = [ "%ProgramFiles%\\WezTerm" ];
      verifier = {
        command = "wezterm";
        args = [ "--version" ];
      };
    };
  };

  testTerminalWingetPackagesRemainInstallableDuringNormalRuns = {
    expr = windows."wez.wezterm".skipInstall or false;
    expected = false;
  };
}
