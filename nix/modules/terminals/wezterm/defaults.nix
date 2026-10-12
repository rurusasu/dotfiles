{ pkgs, ... }:
let
  appearance = import ../appearance.nix;
  weztermLua =
    builtins.replaceStrings
      [ "wezterm.font(\"UDEV Gothic NF\")" ]
      [ "wezterm.font(\"${appearance.font_family}\")" ]
      (builtins.readFile ./wezterm.lua);
in
{
  imports = [ (import ../../tools.nix).wezterm ];
  programs.wezterm = {
    package = pkgs.wezterm;
    settings = {
      color_scheme = appearance.theme;
      font_size = appearance.font_size;
    };
    extraConfig = weztermLua;
    enableBashIntegration = true;
    enableZshIntegration = true;
  };
}
