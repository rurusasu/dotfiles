{ inputs }:
let
  pkgs = (import ../../fixtures/packages.nix { inherit inputs; }).mkPkgs "aarch64-darwin";
  fixtures = import ../../fixtures/packages.nix { inherit inputs; };
  windows = fixtures.windowsPackages;
  home = fixtures.mkHome "aarch64-darwin" [
    (fixtures.homeModule "common")
    ../../../modules/editors/nvim
  ];
  orcaPackage = inputs.llm-agents.packages.aarch64-darwin.orca;
in
{
  testOrcaHomeManagerModuleAndWingetMetadata = {
    expr = {
      orcaPackageSelected = builtins.any (
        package: package.drvPath == orcaPackage.drvPath
      ) home.config.home.packages;
      orcaWindowsProvider = windows."StablyAI.Orca".source;
      orcaCiSkipInstall = windows."StablyAI.Orca".ciSkipInstall or false;
      directPythonInstallation = builtins.elem pkgs.python3 home.config.home.packages;
      uvInstalled = builtins.elem pkgs.uv home.config.home.packages;
    };
    expected = {
      orcaPackageSelected = true;
      orcaWindowsProvider = "winget";
      orcaCiSkipInstall = true;
      directPythonInstallation = false;
      uvInstalled = true;
    };
  };
  testOrcaLinuxHomeManagerPackages = {
    expr =
      map
        (
          system:
          let
            package = inputs.llm-agents.packages.${system}.orca;
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
          pname = "orca";
          inherit (orcaPackage) version;
          mainProgram = "orca-ide";
        })
        [
          "x86_64-linux"
          "aarch64-linux"
        ];
  };
}
