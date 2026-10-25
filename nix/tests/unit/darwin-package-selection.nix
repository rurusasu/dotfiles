{ inputs }:
let
  fixtures = import ../fixtures/packages.nix { inherit inputs; };
  pkgs = fixtures.mkPkgs "aarch64-darwin";
  cfg = fixtures.darwin.config;
  homePackages = cfg.home-manager.users.test-user.home.packages;
  systemPackages = cfg.environment.systemPackages;
  contains = expected: packages: builtins.any (package: package.drvPath == expected.drvPath) packages;
in
{
  testDarwinGuiPromotionsSelectTheirCustomSystemDerivations = {
    expr = contains (import ../../modules/browsers/dia { inherit inputs pkgs; }) systemPackages;
    expected = true;
  };
  testRaycastDerivationIsSelectedForDarwinSystem = {
    expr = contains pkgs.raycast systemPackages;
    expected = true;
  };
  testDarwinTerminalGuiPackagesUseNativeWindowManagerAndTerminals = {
    expr = {
      aerospace = contains pkgs.aerospace homePackages;
      ghostty = contains cfg.home-manager.users.test-user.programs.ghostty.package homePackages;
      wezterm = contains cfg.home-manager.users.test-user.programs.wezterm.package homePackages;
    };
    expected = {
      aerospace = true;
      ghostty = true;
      wezterm = true;
    };
  };
}
