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
  testCodexIsAnAllPlatformNpmPackageAndUsesCliVerifier = {
    expr = {
      mapping = sets.npmMap.codex;
      verifier = sets.npmVerify.codex;
      providers = builtins.map (platform: sets.supportReport.codex.${platform}.provider) [
        "windows"
        "darwin"
        "linux"
      ];
    };
    expected = {
      mapping = "@openai/codex";
      verifier = {
        command = "codex";
        args = [ "--version" ];
      };
      providers = [ "npm" "npm" "npm" ];
    };
  };

  testDevcontainerNpmPackageAndVerifier = {
    expr = {
      nixPackageSelected = builtins.elem pkgs.devcontainer sets.all;
      windowsProvider = sets.supportReport.devcontainer.windows.provider;
      windowsSource = sets.supportReport.devcontainer.windows.source;
      windowsIdentity = sets.supportReport.devcontainer.windows.identity;
      npmMapping = sets.npmMap.devcontainer;
      npmVerify = sets.npmVerify.devcontainer;
    };
    expected = {
      nixPackageSelected = true;
      windowsProvider = "npm";
      windowsSource = "npm";
      windowsIdentity = "@devcontainers/cli";
      npmMapping = "@devcontainers/cli";
      npmVerify = {
        command = "devcontainer";
        args = [ "--version" ];
      };
    };
  };

  testAgentBrowserWindowsOnlyNpmPackageAndVerifier = {
    expr = {
      windowsOnlyNpmPackage = builtins.elem "agent-browser@0.38.1" sets.windowsOnly.npm;
      npmVerify = sets.npmVerify."agent-browser";
    };
    expected = {
      windowsOnlyNpmPackage = true;
      npmVerify = {
        command = "agent-browser";
        args = [ "--version" ];
      };
    };
  };
}
