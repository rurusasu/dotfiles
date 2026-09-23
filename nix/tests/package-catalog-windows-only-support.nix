{ inputs }:
let
  pkgs = import inputs.nixpkgs {
    system = "aarch64-darwin";
    config.allowUnfree = true;
  };
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
