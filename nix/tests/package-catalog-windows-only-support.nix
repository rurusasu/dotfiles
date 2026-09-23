{ inputs }:
let
  pkgs = (import ../test-fixtures.nix { inherit inputs; }).mkPkgs "aarch64-darwin";
  sets = import ../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
  powerToys = sets.supportReport."Microsoft.PowerToys";
in
{
  testPowerToysSupportMetadata = {
    expr = {
      windows = {
        inherit (powerToys.windows) provider identity;
      };
      darwinUnsupported = powerToys.darwin.unsupported;
      linuxUnsupported = powerToys.linux.unsupported;
    };
    expected = {
      windows = {
        provider = "winget";
        identity = "Microsoft.PowerToys";
      };
      darwinUnsupported = "Windows system utility";
      linuxUnsupported = "Windows system utility";
    };
  };
}
