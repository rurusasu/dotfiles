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
  testWezTermDarwinProviderMetadata = {
    expr = sets.supportReport.wezterm;
    expected = {
      darwin = {
        provider = "nix";
        source = "nixpkgs";
        nixAttr = "wezterm";
        identity = {
          appName = "WezTerm.app";
        };
      };
      linux = {
        provider = "nix";
        source = "nixpkgs";
        identity = "wezterm";
        nixAttr = "wezterm";
      };
      windows = {
        provider = "winget";
        source = "winget";
        identity = "wez.wezterm";
      };
      installFeature = null;
    };
  };

  testOllamaDarwinProviderMetadata = {
    expr = sets.supportReport.ollama;
    expected = {
      darwin = {
        provider = "nix";
        source = "nixpkgs";
        nixAttr = "ollama";
        identity = "ollama";
      };
      linux = {
        provider = "nix";
        source = "nixpkgs";
        identity = "ollama";
        nixAttr = "ollama";
      };
      windows = {
        provider = "winget";
        source = "winget";
        identity = "Ollama.Ollama";
      };
      installFeature = "WithOllama";
    };
  };
}
