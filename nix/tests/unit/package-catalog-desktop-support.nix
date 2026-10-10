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
  testGlazeWMIsExcludedFromWindowsInstallation = {
    expr = {
      unsupportedDarwin = sets.supportReport.glazewm.darwin ? unsupported;
      unsupportedLinux = sets.supportReport.glazewm.linux ? unsupported;
      selected = builtins.elem "glazewm" sets.windowsGuiPackages.catalog;
      errors = sets.providerErrors;
    };
    expected = {
      unsupportedDarwin = true;
      unsupportedLinux = true;
      selected = false;
      errors = [ ];
    };
  };

  testWindowsGuiProfileIsExplicitAndExcludesAutomation = {
    expr = sets.windowsGuiPackages;
    expected = {
      catalog = [
        "arc-browser"
        "google-chrome"
        "obsidian"
        "wezterm"
      ];
      windowsOnly = [
        "AgileBits.1Password"
        "Discord.Discord"
        "StablyAI.Orca"
        "Microsoft.PowerToys"
        "Microsoft.WindowsTerminal"
        "9PLM9XGG6VKS"
      ];
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
