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
  testDevcontainerNixAndWindowsNpmMappings = {
    expr = {
      nixPackageSelected = builtins.elem pkgs.devcontainer sets.all;
      darwinProvider = sets.supportReport.devcontainer.darwin.provider;
      darwinSource = sets.supportReport.devcontainer.darwin.source;
      darwinNixAttr = sets.supportReport.devcontainer.darwin.nixAttr;
      windowsProvider = sets.supportReport.devcontainer.windows.provider;
      windowsSource = sets.supportReport.devcontainer.windows.source;
      windowsIdentity = sets.supportReport.devcontainer.windows.identity;
      npmMapping = sets.npmMap.devcontainer;
      npmVerify = sets.npmVerify.devcontainer;
    };
    expected = {
      nixPackageSelected = true;
      darwinProvider = "nix";
      darwinSource = "nixpkgs";
      darwinNixAttr = "devcontainer";
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
}
