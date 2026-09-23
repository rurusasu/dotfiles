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
  testPlaywrightPackagesAreHermesOnly = {
    expr = {
      cliIsGlobalPackage = builtins.elem "@playwright/cli@0.1.21" sets.pnpmGlobal;
      cliInstallFeature = sets.pnpmInstallFeature."@playwright/cli";
      playwrightIsGlobalPackage = builtins.elem "playwright@1.63.0" sets.pnpmGlobal;
      playwrightInstallFeature = sets.pnpmInstallFeature.playwright;
    };
    expected = {
      cliIsGlobalPackage = true;
      cliInstallFeature = "WithHermes";
      playwrightIsGlobalPackage = true;
      playwrightInstallFeature = "WithHermes";
    };
  };
}
