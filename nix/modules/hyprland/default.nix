# User configuration; selected only by the native NixOS host.
{ lib, pkgs, ... }:
{
  wayland.windowManager.hyprland = {
    enable = true;
    # The NixOS module owns compositor/portal packages and session registration.
    package = null;
    portalPackage = null;
    configType = "lua";
    extraConfig =
      (import ./hyprland-renderer.nix {
        inherit lib;
        commands = {
          terminal = "wezterm start --always-new-process";
          browser = "firefox --new-window";
          files = "nautilus --new-window";
          notes = "obsidian";
          ai = "chatgpt";
          passwords = "1password";
          launcher = "fuzzel";
          help = "wezterm start --always-new-process -- less ${pkgs.writeText "omarchy-keybindings.txt" (builtins.readFile ../../../docs/chezmoi/omarchy.md)}";
          activity = "wezterm start --always-new-process -- top";
        };
      }).config;
  };
}
