{ inputs }:
let
  pkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs "aarch64-darwin";
  sets = import ../../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
in
{
  testWezTermDarwinProviderMetadata = {
    expr = sets.supportReport.wezterm;
    expected = {
      darwin = {
        unsupported = "WezTerm is managed by Home Manager";
      };
      linux = {
        unsupported = "WezTerm is managed by Home Manager";
      };
      windows = {
        provider = "winget";
        source = "winget";
        identity = "wez.wezterm";
      };
      installFeature = null;
    };
  };

}
