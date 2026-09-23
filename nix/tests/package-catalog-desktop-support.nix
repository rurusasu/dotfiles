{ inputs }:
let
  pkgs = import inputs.nixpkgs {
    system = "aarch64-darwin";
    config.allowUnfree = true;
  };
  sets = import ../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
in
{
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
