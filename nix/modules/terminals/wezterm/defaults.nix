{
  config,
  lib,
  pkgs,
  ...
}:
let
  appearance = import ../appearance.nix;
  weztermLua =
    builtins.replaceStrings
      [ "wezterm.font(\"UDEV Gothic NF\")" ]
      [ "wezterm.font(\"${appearance.font_family}\")" ]
      (builtins.readFile ./wezterm.lua);
  shellIntegration = ''
    if [ "''${TERM_PROGRAM-}" = "WezTerm" ]; then
      source "${config.programs.wezterm.package}/etc/profile.d/wezterm.sh"
    fi
  '';
in
{
  imports = [ (import ../../tools.nix).wezterm ];
  programs.wezterm = {
    package = pkgs.wezterm;
    settings = {
      color_scheme = appearance.theme;
      inherit (appearance) font_size;
    };
    extraConfig = weztermLua;
    # The upstream integration installs prompt/OSC hooks in every terminal.
    # Scope it to WezTerm so Ghostty can use its own shell integration.
    enableBashIntegration = false;
    enableZshIntegration = false;
  };
  programs.bash.initExtra = shellIntegration;
  programs.zsh.initContent = lib.mkOrder 1000 shellIntegration;
}
