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
  testDiaPreservesPlatformSupportIdentity = {
    expr = sets.supportReport.dia-browser;
    expected = {
      installFeature = null;
      windows = {
        unsupported = "Vendor currently ships Dia for macOS only";
      };
      darwin = {
        provider = "nix";
        source = "custom";
        identity = {
          appName = "Dia.app";
        };
      };
      linux = {
        unsupported = "Vendor currently ships Dia for macOS only";
      };
    };
  };

  testArcPreservesWindowsProviderAndDarwinUnsupportedReason = {
    expr = {
      windows = sets.supportReport.arc-browser.windows;
      darwin = sets.supportReport.arc-browser.darwin;
    };
    expected = {
      windows = {
        provider = "winget";
        source = "winget";
        identity = "TheBrowserCompany.Arc";
      };
      darwin = {
        unsupported = "Use Dia instead of Arc on macOS";
      };
    };
  };
}
