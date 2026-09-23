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
  testOrcaDarwinProviderAndWingetMetadata = {
    expr = {
      orcaDarwinProvider = sets.supportReport.orca-editor.darwin.provider;
      orcaDarwinSource = sets.supportReport.orca-editor.darwin.source;
      orcaLegacyDarwin = sets.supportReport.orca-editor.legacyDarwin;
      orcaIsDesktopPackage = builtins.elem sets.darwinPackages.orca-editor sets.desktop;
      orcaWingetId = sets.wingetMap.orca-editor;
      orcaInWindowsOnlyWinget = builtins.elem "StablyAI.Orca" sets.windowsOnly.winget;
      orcaCiSkipInstall = sets.wingetCiSkipInstall."StablyAI.Orca" or false;
      pythonResolvedInNix = builtins.elem pkgs.python3 sets.all;
      pythonHasWingetMapping = builtins.hasAttr "python3" sets.wingetMap;
      legacyPythonWingetIdPresent = builtins.elem "Python.Python.3.13" (
        builtins.attrValues sets.wingetMap
      );
      uvResolvedInNix = builtins.elem pkgs.uv sets.all;
      uvWingetId = sets.wingetMap.uv;
    };
    expected = {
      orcaDarwinProvider = "nix";
      orcaDarwinSource = "custom";
      orcaLegacyDarwin = {
        provider = "homebrew-cask";
        name = "stablyai/orca/orca";
      };
      orcaIsDesktopPackage = true;
      orcaWingetId = "StablyAI.Orca";
      orcaInWindowsOnlyWinget = false;
      orcaCiSkipInstall = true;
      pythonResolvedInNix = true;
      pythonHasWingetMapping = false;
      legacyPythonWingetIdPresent = false;
      uvResolvedInNix = true;
      uvWingetId = "astral-sh.uv";
    };
  };
}
