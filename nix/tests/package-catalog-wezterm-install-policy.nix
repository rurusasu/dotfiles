{ inputs }:
let
  pkgs = (import ../test-fixtures.nix { inherit inputs; }).mkPkgs "aarch64-darwin";
  sets = import ../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
  terminalWingetPackages = {
    autohotkey = "AutoHotkey.AutoHotkey";
    starship = "Starship.Starship";
    wezterm = "wez.wezterm.nightly";
  };
  terminalWingetMap = builtins.intersectAttrs terminalWingetPackages sets.wingetMap;
  terminalSkipKeys =
    builtins.attrNames terminalWingetPackages ++ builtins.attrValues terminalWingetMap;
in
{
  testWeztermNightlyDoesNotRequireInstallerHashOverride = {
    expr = builtins.elem "--ignore-security-hash" (sets.wingetInstallArgs.wezterm or [ ]);
    expected = false;
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
