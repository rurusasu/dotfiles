{ inputs }:
let
  pkgs = (import ../test-fixtures.nix { inherit inputs; }).mkPkgs "x86_64-linux";
  sets = import ../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
  netcat = sets.supportReport.netcat;
in
{
  testNetcatUsesNixpkgsAndHasReviewedWindowsUnsupportedReason = {
    expr = {
      selected = builtins.elem pkgs.netcat sets.core;
      winget = sets.supportReport.netcat.windows.provider or null;
      windowsUnsupported = netcat.windows.unsupported or null;
    };
    expected = {
      selected = true;
      winget = null;
      windowsUnsupported = "No reviewed Windows package provider is selected";
    };
  };
}
