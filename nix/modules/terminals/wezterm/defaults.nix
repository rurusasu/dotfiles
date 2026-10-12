{ pkgs, ... }:
{
  imports = [ (import ../../tools.nix).wezterm ];
  programs.wezterm = {
    package = pkgs.wezterm;
    settings = {
      color_scheme = "Catppuccin Mocha";
      font_size = 10;
    };
    extraConfig = builtins.readFile ./wezterm.lua;
    enableBashIntegration = true;
    enableZshIntegration = true;
  };
}
