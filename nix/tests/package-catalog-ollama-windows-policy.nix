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
  testOllamaWingetVerifierContract = {
    expr = {
      inherit (sets.wingetVerify.ollama) command args;
    };
    expected = {
      command = "ollama";
      args = [ "--version" ];
    };
  };

  testOllamaUsesWindowsInstallFeature = {
    expr = sets.wingetFeatureMap.ollama;
    expected = "WithOllama";
  };
}
