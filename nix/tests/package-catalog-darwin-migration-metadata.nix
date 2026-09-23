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
  testWezTermDarwinMigrationMetadata = {
    expr = sets.supportReport.wezterm;
    expected = {
      darwin = {
        provider = "nix";
        source = "nixpkgs";
        nixAttr = "wezterm";
        identity = {
          homepage = "https://wezterm.org/";
          appName = "WezTerm.app";
          bundleId = "com.github.wez.wezterm";
          executable = "wezterm-gui";
        };
      };
      linux = {
        provider = "nix";
        source = "nixpkgs";
        identity = "wezterm";
        nixAttr = "wezterm";
      };
      installFeature = null;
      legacyDarwin = {
        provider = "homebrew-cask";
        name = "wezterm@nightly";
      };
    };
  };

  testOllamaDarwinMigrationMetadata = {
    expr = sets.supportReport.ollama;
    expected = {
      darwin = {
        provider = "nix";
        source = "nixpkgs";
        nixAttr = "ollama";
        identity = {
          homepage = "https://ollama.com/";
          command = "ollama";
          versionArgs = [ "--version" ];
        };
      };
      linux = {
        provider = "nix";
        source = "nixpkgs";
        identity = "ollama";
        nixAttr = "ollama";
      };
      installFeature = "WithOllama";
      legacyDarwin = {
        provider = "homebrew-cask";
        name = "ollama-app";
      };
    };
  };
}
