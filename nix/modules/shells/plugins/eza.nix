{ pkgs, ... }:
{
  programs.eza = {
    enable = true;
    package = pkgs.eza;
  };
}
