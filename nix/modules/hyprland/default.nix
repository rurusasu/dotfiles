# User configuration; selected only by the native NixOS host.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  terminal =
    if config.programs.ghostty.enable && config.programs.ghostty.package != null then
      lib.escapeShellArg (lib.getExe config.programs.ghostty.package)
    else
      "ghostty";
in
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
            inherit terminal;
            browser = "firefox --new-window";
            files = "nautilus --new-window";
            notes = "obsidian";
            ai = "chatgpt";
            passwords = "1password";
            launcher = "fuzzel";
            help = "${terminal} -e less ${pkgs.writeText "omarchy-keybindings.txt" (builtins.readFile ../../../docs/chezmoi/omarchy.md)}";
            activity = "${terminal} -e top";
          };
        }).config;
    };
  };
}
