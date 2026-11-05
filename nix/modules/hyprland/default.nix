# User configuration; selected only by the native NixOS host.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.wayland.windowManager.hyprland.enable {
    wayland.windowManager.hyprland = {
      # The NixOS module owns compositor/portal packages and session registration.
      package = null;
      portalPackage = null;
      configType = "lua";
      extraConfig =
        (import ./hyprland-renderer.nix {
          inherit lib;
          commands = {
            terminal = "alacritty";
            browser = "firefox --new-window";
            files = "nautilus --new-window";
            notes = "obsidian";
            ai = "chatgpt";
            passwords = "1password";
            launcher = "fuzzel";
            help = "alacritty -e less ${pkgs.writeText "omarchy-keybindings.txt" (builtins.readFile ../../../docs/chezmoi/omarchy.md)}";
            activity = "alacritty -e top";
          };
        }).config;
    };
  };
}
