{ inputs }:
let
  pkgs = (import ../test-fixtures.nix { inherit inputs; }).mkPkgs "aarch64-darwin";
  sets = import ../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
  codexDesktop = sets.supportReport."9PLM9XGG6VKS";
in
{
  testCodexDesktopIsWindowsOnlyMicrosoftStorePackage = {
    expr = {
      windowsOnlyMsstore = builtins.elem "9PLM9XGG6VKS" sets.windowsOnly.msstore;
      provider = codexDesktop.windows.provider;
      source = codexDesktop.windows.source;
      identity = codexDesktop.windows.identity;
      darwinUnsupported = codexDesktop.darwin.unsupported or null;
      linuxUnsupported = codexDesktop.linux.unsupported or null;
    };
    expected = {
      windowsOnlyMsstore = true;
      provider = "msstore";
      source = "msstore";
      identity = "9PLM9XGG6VKS";
      darwinUnsupported = "Windows Store desktop application";
      linuxUnsupported = "Windows Store desktop application";
    };
  };
}
