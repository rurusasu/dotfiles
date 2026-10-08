{ inputs }:
let
  pkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs "aarch64-darwin";
  sets = import ../../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
  terminalWingetPackages = {
    autohotkey = "AutoHotkey.AutoHotkey";
    wezterm = "wez.wezterm";
  };
  terminalWingetMap = builtins.intersectAttrs terminalWingetPackages sets.wingetMap;
  terminalSkipKeys =
    builtins.attrNames terminalWingetPackages ++ builtins.attrValues terminalWingetMap;
in
{
  testWeztermStablePackageDoesNotRequireInstallerHashOverride = {
    expr = builtins.elem "--ignore-security-hash" (sets.wingetInstallArgs.wezterm or [ ]);
    expected = false;
  };

  testWeztermCommonWindowsInstallRemainsInCi = {
    expr = {
      ciSkipped = sets.wingetCiSkipInstall.wezterm or false;
      pathEntries = sets.wingetPathEntries.wezterm;
      verifier = sets.wingetVerify.wezterm;
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
    expr = {
      wingetMap = terminalWingetMap;
      skippedPackages = builtins.filter (key: builtins.elem key terminalSkipKeys) (
        builtins.attrNames sets.wingetSkipInstall
      );
    };
    expected = {
      wingetMap = terminalWingetPackages;
      skippedPackages = [ ];
    };
  };
}
