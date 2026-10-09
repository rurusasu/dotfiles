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

  testGoogleChromePreservesWindowsProviderAndDarwinIdentity = {
    expr = sets.supportReport.google-chrome;
    expected = {
      installFeature = null;
      windows = {
        provider = "winget";
        source = "winget";
        identity = "Google.Chrome";
      };
      darwin = {
        provider = "nix";
        source = "nixpkgs";
        identity = {
          appName = "Google Chrome.app";
        };
        nixAttr = "google-chrome";
      };
      linux = {
        provider = "nix";
        source = "nixpkgs";
        identity = "google-chrome";
        nixAttr = "google-chrome";
      };
    };
  };

  testRaycastPreservesUnsupportedReasonsAndDarwinIdentity = {
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
          appName = "Raycast.app";
        };
        nixAttr = "raycast";
      };
    };
  };

  testTartPreservesAppleSiliconRequirementsAndDarwinIdentity = {
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
        identity = "tart";
        nixAttr = "tart";
      };
    };
  };
}
