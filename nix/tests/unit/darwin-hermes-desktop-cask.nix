{ inputs }:
let
  system = "aarch64-darwin";
  pkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs system;
  sets = import ../../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
in
{
  testHermesDesktopIsNotInstalledThroughHomebrewCask = {
    expr = builtins.elem "hermes-desktop" sets.darwinCasks;
    expected = false;
  };
}
