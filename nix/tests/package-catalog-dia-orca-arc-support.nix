{ inputs }:
let
  pkgs = (import ../test-fixtures.nix { inherit inputs; }).mkPkgs "aarch64-darwin";
  sets = import ../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
in
{
  testDiaPreservesPlatformSupportIdentityAndLegacyCask = {
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
          homepage = "https://www.diabrowser.com/";
          appName = "Dia.app";
          bundleId = "company.thebrowser.dia";
          executable = "Dia";
        };
      };
      linux = {
        unsupported = "Vendor currently ships Dia for macOS only";
      };
      legacyDarwin = {
        provider = "homebrew-cask";
        name = "thebrowsercompany-dia";
      };
    };
  };

  testOrcaPreservesFullDarwinApplicationIdentity = {
    expr = sets.supportReport.orca-editor.darwin.identity;
    expected = {
      homepage = "https://onorca.dev/";
      appName = "Orca.app";
      bundleId = "com.stablyai.orca";
      executable = "Orca";
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
