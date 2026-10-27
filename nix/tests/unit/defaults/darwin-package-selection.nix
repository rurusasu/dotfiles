{
  inputs,
  fixtures,
  code,
}:
let
  pkgs = fixtures.mkPkgs "aarch64-darwin";
  cfg = fixtures.darwin.config;
  homePackages = cfg.home-manager.users.test-user.home.packages;
  contains = expected: packages: builtins.any (package: package.drvPath == expected.drvPath) packages;
in
{
  testDarwinDiaUsesItsCustomHomeDerivation = {
    expr = contains (code.nix.modules.browsers.dia.package {
      inherit inputs pkgs;
    }) homePackages;
    expected = true;
  };
  testRaycastDerivationIsSelectedForDarwinHome = {
    expr = contains pkgs.raycast homePackages;
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
