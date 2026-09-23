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
  dockerSupport = sets.supportReport.docker-desktop;
in
{
  testPackageProviderCoverageOutputs = {
    expr = {
      supportReport = {
        isAttrs = builtins.isAttrs sets.supportReport;
        dockerWindowsProvider = dockerSupport.windows.provider;
        dockerDarwinProvider = dockerSupport.darwin.provider;
        dockerLinuxProvider = dockerSupport.linux.provider;
      };
      providerErrors = sets.providerErrors;
      darwinCasks = {
        isList = builtins.isList sets.darwinCasks;
        hasDockerDesktop = builtins.elem "docker-desktop" sets.darwinCasks;
        hasHermesDesktop = builtins.elem "hermes-desktop" sets.darwinCasks;
      };
      linuxSystemModules = {
        isList = builtins.isList sets.linuxSystemModules;
        hasDocker = builtins.elem "docker" sets.linuxSystemModules;
      };
    };
    expected = {
      supportReport = {
        isAttrs = true;
        dockerWindowsProvider = "winget";
        dockerDarwinProvider = "homebrew-cask";
        dockerLinuxProvider = "system-manager";
      };
      providerErrors = [ ];
      darwinCasks = {
        isList = true;
        hasDockerDesktop = true;
        hasHermesDesktop = true;
      };
      linuxSystemModules = {
        isList = true;
        hasDocker = true;
      };
    };
  };
}
