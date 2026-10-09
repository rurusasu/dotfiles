{ inputs }:
let
  pkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs "aarch64-darwin";
  sets = import ../../packages/sets.nix {
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
        dockerLinuxReason = dockerSupport.linux.unsupported;
      };
      inherit (sets) providerErrors;
      darwinCasks = {
        isList = builtins.isList sets.darwinCasks;
        hasDockerDesktop = builtins.elem "docker-desktop" sets.darwinCasks;
        hasHermesDesktop = builtins.elem "hermes-desktop" sets.darwinCasks;
      };
    };
    expected = {
      supportReport = {
        isAttrs = true;
        dockerWindowsProvider = "winget";
        dockerDarwinProvider = "homebrew-cask";
        dockerLinuxReason = "Docker Desktop is not selected on Linux; NixOS manages the Docker engine through virtualisation.docker";
      };
      providerErrors = [ ];
      darwinCasks = {
        isList = true;
        hasDockerDesktop = true;
        hasHermesDesktop = true;
      };
    };
  };
}
