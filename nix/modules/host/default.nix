{ config, pkgs, ... }:
{
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
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

  environment.systemPackages = [
    pkgs.git
  ];
}
