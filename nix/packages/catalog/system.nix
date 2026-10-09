# Package identities and provider declarations for system.
{ pkgs, ... }:
{
  tart = {
    pkg = pkgs.tart;
    category = "system";
    support = {
      windows = {
        unsupported = "Tart requires Apple Silicon macOS";
      };
      darwin = {
        provider = "nix";
        source = "nixpkgs";
        nixAttr = "tart";
        identity = "tart";
      };
      linux = {
        unsupported = "Tart requires Apple Silicon macOS";
      };
    };
  };

  docker-desktop = {
    winget = "Docker.DockerDesktop";
    category = "system";
    support = {
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
    };
  };
}
