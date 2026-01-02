{ config, pkgs, ... }:
{
  imports = [
    ../users/nixos.nix
    ../../profiles/home/common.nix
  ];
}
