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
    category = "system";
    support = {
      windows = {
        unsupported = "Docker Desktop is not installed on Windows; NixOS-WSL runs directly as a WSL distribution";
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
