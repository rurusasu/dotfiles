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
  testGlazeWMIsWindowsOnlyAndMachineInstalled = {
    expr = {
      windows = sets.supportReport.glazewm.windows;
      unsupportedDarwin = sets.supportReport.glazewm.darwin ? unsupported;
      unsupportedLinux = sets.supportReport.glazewm.linux ? unsupported;
      id = sets.wingetMap.glazewm;
      admin = sets.wingetRequiresAdmin.glazewm;
      args = sets.wingetInstallArgs.glazewm;
      verify = sets.wingetVerify.glazewm;
      path = sets.wingetPathEntries.glazewm;
    };
    expected = {
      windows = {
        provider = "winget";
        source = "winget";
        identity = "glzr-io.glazewm";
      };
      unsupportedDarwin = true;
      unsupportedLinux = true;
      id = "glzr-io.glazewm";
      admin = true;
      args = [
        "--scope"
        "machine"
      ];
      verify = {
        command = "glazewm";
        args = [ "--version" ];
      };
      path = [ "%ProgramFiles%\\glzr.io\\GlazeWM" ];
    };
  };

  testGoogleChromePreservesWindowsProviderAndDarwinMigration = {
    expr = sets.supportReport.google-chrome;
    expected = {
      installFeature = "WithHermes";
      windows = {
        provider = "winget";
        source = "winget";
        identity = "Google.Chrome";
      };
      darwin = {
        provider = "nix";
        source = "nixpkgs";
        identity = {
          homepage = "https://www.google.com/chrome/";
          appName = "Google Chrome.app";
          bundleId = "com.google.Chrome";
          executable = "Google Chrome";
        };
        nixAttr = "google-chrome";
      };
      linux = {
        provider = "nix";
        source = "nixpkgs";
        identity = "google-chrome";
        nixAttr = "google-chrome";
      };
      legacyDarwin = {
        provider = "homebrew-cask";
        name = "google-chrome";
      };
    };
  };

  testRaycastPreservesUnsupportedReasonsAndDarwinMigration = {
    expr = sets.supportReport.raycast;
    expected = {
      installFeature = null;
      windows = {
        unsupported = "Managed only on macOS in this dotfiles profile";
      };
      linux = {
        unsupported = "Vendor does not publish a Linux build";
      };
      darwin = {
        provider = "nix";
        source = "nixpkgs";
        identity = {
          homepage = "https://raycast.com/";
          appName = "Raycast.app";
          bundleId = "com.raycast.macos";
          executable = "Raycast";
        };
        nixAttr = "raycast";
      };
      legacyDarwin = {
        provider = "homebrew-cask";
        name = "raycast";
      };
    };
  };

  testTartPreservesAppleSiliconRequirementsAndDarwinMigration = {
    expr = sets.supportReport.tart;
    expected = {
      installFeature = null;
      windows = {
        unsupported = "Tart requires Apple Silicon macOS";
      };
      linux = {
        unsupported = "Tart requires Apple Silicon macOS";
      };
      darwin = {
        provider = "nix";
        source = "nixpkgs";
        identity = {
          homepage = "https://tart.run/";
          command = "tart";
          versionArgs = [ "--version" ];
        };
        nixAttr = "tart";
      };
      legacyDarwin = {
        provider = "homebrew-formula";
        name = "openai/tools/tart";
      };
    };
  };
}
