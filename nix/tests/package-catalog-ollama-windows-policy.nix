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
