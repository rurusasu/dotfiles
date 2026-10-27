{ inputs }:
let
  fixtures = import ../../../../fixtures/packages.nix { inherit inputs; };
  disabled = fixtures.mkHome "aarch64-darwin" [ ];
  enabled = fixtures.mkHome "aarch64-darwin" [ { programs.dia.enable = true; } ];
  package = import ../../../../../modules/browsers/dia/package.nix {
    inherit inputs;
    pkgs = fixtures.mkPkgs "aarch64-darwin";
  };
in
{
  testDiaCanBeEnabledThroughItsTypedOption = {
    expr = {
      disabled = disabled.config.programs.dia.enable;
      absent = !(builtins.elem disabled.config.programs.dia.package disabled.config.home.packages);
      selected = builtins.elem enabled.config.programs.dia.package enabled.config.home.packages;
    };
    expected = {
      disabled = false;
      absent = true;
      selected = true;
    };
  };
  testDiaUsesTheCustomDarwinPackage = {
    expr = {
      selected = builtins.elem package fixtures.darwin.config.home-manager.users.test-user.home.packages;
      platforms = package.meta.platforms;
    };
    expected = {
      selected = true;
      platforms = [ "aarch64-darwin" ];
    };
  };
}
