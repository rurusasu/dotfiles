{ config, pkgs, ... }:
{
  imports = [
    ../../modules/host
    ../../modules/wsl
    ./configuration.nix
  ];

  users.users.nixos.shell = pkgs.zsh;
}
