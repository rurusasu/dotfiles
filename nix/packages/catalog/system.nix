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
        identity = {
          homepage = "https://tart.run/";
          command = "tart";
          versionArgs = [ "--version" ];
        };
      };
      linux = {
        unsupported = "Tart requires Apple Silicon macOS";
      };
    };
    legacyDarwin = {
      provider = "homebrew-formula";
      name = "openai/tools/tart";
    };
  };

  docker-desktop = {
    winget = "Docker.DockerDesktop";
    category = "system";
    installFeature = "WithDocker";
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
        provider = "system-manager";
        source = "nixpkgs";
        identity = "docker";
        nixAttr = "docker";
        systemModule = "docker";
      };
    };
  };
}
