# Standalone Darwin identity; hosted homes inherit their directory from nix-darwin.
{ config, lib, ... }:
{
  home.homeDirectory = lib.mkDefault "/Users/${config.home.username}";
}
