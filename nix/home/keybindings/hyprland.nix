# User configuration; selected only by the native NixOS host.
{ lib, pkgs, ... }:
let
  sets = import ../../packages/sets.nix { inherit pkgs lib; };
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
      ai = "firefox --new-window https://chatgpt.com";
      passwords = "1password";
      launcher = "fuzzel";
      help = "wezterm start --always-new-process -- less ${help}";
      activity = "wezterm start --always-new-process -- top";
    };
  };
in
{
  home.packages = sets.resolveForInstallFeatures [ "WithDesktop" ] (
    builtins.filter (name: name != "hyprland") sets.nativeDesktopPackageNames
  );
  wayland.windowManager.hyprland = {
    enable = true;
    # The NixOS module owns compositor/portal packages and session registration.
    package = null;
    portalPackage = null;
    configType = "lua";
    extraConfig = rendered.config;
  };
}
