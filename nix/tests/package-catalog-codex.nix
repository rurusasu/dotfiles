{ inputs }:
let
  system = "aarch64-darwin";
  pkgs = (import ../test-fixtures.nix { inherit inputs; }).mkPkgs system;
  sets = import ../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
  support = sets.supportReport.codex;
in
{
  testCodexUsesNpmOnEverySupportedPlatform = {
    expr = {
      providerErrors = sets.providerErrors;
      nixPackageSelected = builtins.elem pkgs.hello sets.all;
      npmMapping = sets.npmMap.codex;
      npmVerify = sets.npmVerify.codex;
      support = {
        windows = {
          inherit (support.windows) provider source identity;
        };
        darwin = {
          inherit (support.darwin) provider source identity;
        };
        linux = {
          inherit (support.linux) provider source identity;
        };
      };
    };
    expected = {
      providerErrors = [ ];
      nixPackageSelected = false;
      npmMapping = "@openai/codex";
      npmVerify = {
        command = "codex";
        args = [ "--version" ];
      };
      support = {
        windows = {
          provider = "npm";
          source = "npm";
          identity = "@openai/codex";
        };
        darwin = {
          provider = "npm";
          source = "npm";
          identity = "@openai/codex";
        };
        linux = {
          provider = "npm";
          source = "npm";
          identity = "@openai/codex";
        };
      };
    };
  };
}
