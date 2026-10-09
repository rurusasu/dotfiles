{ lib, pkgs, ... }:
{
  home.packages = [ pkgs.ghq ];
  programs.git.settings.ghq.root = lib.mkDefault "~/ghq";
}
