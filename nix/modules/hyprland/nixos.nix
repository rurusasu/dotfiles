{ lib, platform, ... }: {
  config = lib.mkIf (platform == "linux") { programs.hyprland.enable = true; };
}
