{ inputs }:
let
  pkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs "aarch64-darwin";
  sets = import ../../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
  orcaModule = import ../../modules/editors/orca { inherit pkgs; };
  orcaPackage = pkgs.callPackage ../../modules/editors/orca/package.nix { };
in
{
  testOrcaHomeManagerModuleAndWingetMetadata = {
    expr = {
      orcaModulePackages = map (package: package.drvPath) orcaModule.home.packages;
      orcaCommonImportsModule =
        builtins.elem ../../modules/editors/orca
          (import ../../home/common.nix {
            config = { };
            inherit (pkgs) lib;
          }).imports;
      orcaWindowsProvider = sets.supportReport."StablyAI.Orca".windows.provider;
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
      orcaModulePackages = [ orcaPackage.drvPath ];
      orcaCommonImportsModule = true;
      orcaWindowsProvider = "winget";
      orcaInWindowsOnlyWinget = true;
      orcaCiSkipInstall = true;
      pythonResolvedInNix = true;
      pythonHasWingetMapping = false;
      legacyPythonWingetIdPresent = false;
      uvResolvedInNix = true;
      uvWingetId = "astral-sh.uv";
    };
  };
  testOrcaLinuxHomeManagerPackages = {
    expr =
      map
        (
          system:
          let
            linuxPkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs system;
            package = builtins.head (import ../../modules/editors/orca { pkgs = linuxPkgs; }).home.packages;
          in
          {
            inherit system;
            inherit (package) pname version;
            mainProgram = package.meta.mainProgram;
          }
        )
        [
          "x86_64-linux"
          "aarch64-linux"
        ];
    expected =
      map
        (system: {
          inherit system;
          pname = "orca-editor";
          inherit (orcaPackage) version;
          mainProgram = "orca-ide";
        })
        [
          "x86_64-linux"
          "aarch64-linux"
        ];
  };
}
