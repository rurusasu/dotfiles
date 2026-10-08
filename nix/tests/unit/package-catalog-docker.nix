{ inputs }:
let
  system = "aarch64-darwin";
  pkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs system;
  sets = import ../../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
  support = sets.supportReport.docker-desktop;
in
{
  testDockerProviderMetadataAndCask = {
    expr = {
      inherit (support) installFeature;
      windows = {
        inherit (support.windows) provider source identity;
      };
      darwin = {
        inherit (support.darwin)
          provider
          source
          identity
          cask
          ;
      };
      inherit (support) linux;
      legacyDarwin = support.legacyDarwin or null;
      included = builtins.elem "docker-desktop" sets.darwinCasks;
    };
    expected = {
      installFeature = null;
      windows = {
        provider = "winget";
        source = "winget";
        identity = "Docker.DockerDesktop";
      };
      darwin = {
        provider = "homebrew-cask";
        source = "homebrew";
        identity = "docker-desktop";
        cask = "docker-desktop";
      };
      linux = {
        unsupported = "Docker Desktop is not selected on Linux; NixOS manages the Docker engine through virtualisation.docker";
      };
      legacyDarwin = null;
      included = true;
    };
  };
}
