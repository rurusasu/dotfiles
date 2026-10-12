{ inputs }:
let
  fixtures = import ../fixtures/packages.nix { inherit inputs; };
  pkgs = fixtures.mkPkgs "aarch64-darwin";
  cfg = fixtures.darwin.config;
  homePackages = cfg.home-manager.users.test-user.home.packages;
  systemPackages = cfg.environment.systemPackages;
  dia = import ../../modules/browsers/dia { inherit pkgs; };
  contains = expected: packages: builtins.any (package: package.drvPath == expected.drvPath) packages;
in
{
  testDarwinGuiPackagesUseSystemAndCommandsUseHomeManager = {
    expr = {
      guiSystem = contains pkgs.obsidian systemPackages;
      guiHome = contains pkgs.obsidian homePackages;
      commandSystem = contains pkgs.jq systemPackages;
      commandHome = contains pkgs.jq homePackages;
    };
    expected = {
      guiSystem = true;
      guiHome = false;
      commandSystem = false;
      commandHome = true;
    };
  };
  testDarwinGuiPromotionsSelectTheirCustomSystemDerivations = {
    expr = {
      system = contains dia systemPackages;
      home = contains dia homePackages;
    };
    expected = {
      system = true;
      home = false;
    };
  };
  testRaycastDerivationIsSelectedForDarwinSystem = {
    expr = contains pkgs.raycast systemPackages;
    expected = true;
  };
  testDarwinTerminalGuiPackagesUseNativeWindowManagerAndTerminals = {
    expr = {
      aerospace = contains pkgs.aerospace systemPackages;
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
