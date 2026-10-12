# User configuration; selected only by the native NixOS host.
{ lib, pkgs, ... }:
let
  help = pkgs.writeText "omarchy-keybindings.txt" (
    builtins.readFile ../../../docs/chezmoi/omarchy.md
  );
  rendered = import ./hyprland-renderer.nix {
    inherit lib;
    commands = {
      terminal = "wezterm start --always-new-process";
      browser = "firefox --new-window";
      files = "nautilus --new-window";
      notes = "obsidian";
      ai = "chatgpt";
      passwords = "1password";
      launcher = "fuzzel";
      help = "wezterm start --always-new-process -- less ${help}";
      activity = "wezterm start --always-new-process -- top";
    };
  };
in
{
  imports = [ (import ../../modules/tools.nix).nativeDesktop ];
  wayland.windowManager.hyprland = {
    enable = true;
    # The NixOS module owns compositor/portal packages and session registration.
    package = null;
    portalPackage = null;
    configType = "lua";
    extraConfig = rendered.config;
  };
}
