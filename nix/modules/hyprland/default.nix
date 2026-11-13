# User configuration; selected only by the native NixOS host.
{
  config,
  pkgs,
  platform,
  lib,
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
  config = lib.mkMerge [
    {
      wayland.windowManager.hyprland.enable = lib.mkIf (
        platform == "linux" && config.submoduleSupport.enable
      ) true;
    }
    (lib.mkIf config.wayland.windowManager.hyprland.enable {
      wayland.windowManager.hyprland = {
        # The NixOS module owns compositor/portal packages and session registration.
        package = null;
        portalPackage = null;
        configType = "lua";
        settings.bind =
          (import ./hyprland-renderer.nix {
            inherit lib;
            commands = {
              inherit terminal;
              browser = "${lib.getExe config.programs.chromium.finalPackage} --new-window";
              notes = "obsidian";
              ai = "chatgpt";
              passwords = "1password";
              help = "${terminal} -e less ${../../../docs/chezmoi/omarchy.md}";
              activity = "${terminal} -e top";
            };
          }).bindings;
      };
    })
  ];
}
