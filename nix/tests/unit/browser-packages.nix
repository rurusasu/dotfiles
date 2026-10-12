{ inputs }:
let
  fixtures = import ../fixtures/packages.nix { inherit inputs; };
  pkgs = fixtures.mkPkgs "aarch64-darwin";
  package = import ../../modules/browsers/dia { inherit pkgs; };
in
{
  testDiaUsesTheCustomDarwinPackage = {
    expr = {
      selected = builtins.elem package fixtures.darwin.config.environment.systemPackages;
      platforms = package.meta.platforms;
    };
    expected = {
      selected = true;
      platforms = [ "aarch64-darwin" ];
    };
  };
  testArcPreservesWindowsDistribution = {
    expr = fixtures.windowsPackages."TheBrowserCompany.Arc".source;
    expected = "winget";
  };
}
