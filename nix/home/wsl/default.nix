{ config, pkgs, ... }:
{
  imports = [
    ../../profiles/home/common.nix
  ];

  home.username = "nixos";
  home.homeDirectory = "/home/nixos";
}
