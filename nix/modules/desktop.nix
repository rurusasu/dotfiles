# Linux GUI applications shared by native Linux and WSLg.
{ pkgs, ... }:
{
  home.packages = [
    pkgs.google-chrome
    pkgs.obsidian
  ];
}
