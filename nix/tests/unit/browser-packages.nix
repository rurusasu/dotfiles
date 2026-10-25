{ inputs }:
let
  fixtures = import ../fixtures/packages.nix { inherit inputs; };
  package = import ../../modules/browsers/dia {
    inherit inputs;
    pkgs = fixtures.mkPkgs "aarch64-darwin";
  };
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
}
