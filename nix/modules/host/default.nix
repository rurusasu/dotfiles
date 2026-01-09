{ lib, pkgs, ... }:
let
  inherit (lib) mkOption types;
in
{
  options.mySettings.wsl.dockerDesktopIntegration = mkOption {
    type = types.bool;
    default = false;
    description = "Enable Docker Desktop WSL2 integration handling for k3s";
  };

  config = {
    nix = {
      settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        auto-optimise-store = true;
      };
      gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 7d";
      };
    };

    nixpkgs.config.allowUnfree = true;
    programs.zsh.enable = true;

    programs.git = {
      enable = true;
      config = {
        safe.directory = "*";
      };
    };

    environment.systemPackages = with pkgs; [
      git
    ];
  };
}
