{ inputs }:
let
  system = "aarch64-darwin";
  pkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs system;
  sets = import ../../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
  hermesSupport = sets.supportReport.hermes-desktop;
in
{
  testHermesDesktopCaskSupportMetadata = {
    expr = {
      inherit (hermesSupport) installFeature;
      darwinSupport = hermesSupport.darwin;
      included = builtins.elem "hermes-desktop" sets.darwinCasks;
    };
    expected = {
      installFeature = null;
      darwinSupport = {
        provider = "homebrew-cask";
        source = "homebrew";
        identity = "hermes-desktop";
        cask = "hermes-desktop";
      };
      included = true;
    };
  };
}
