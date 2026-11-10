# WSLg graphics variables belong to the GPU integration module.
{ lib, platform, ... }:
let
  graphics = {
    LD_LIBRARY_PATH = "/run/opengl-driver/lib";
    GALLIUM_DRIVER = "d3d12";
    WARP_ENABLE_WAYLAND = "1";
  };
in
{
  config = lib.mkIf (platform == "wsl") {
    home.sessionVariables = graphics;
    systemd.user.sessionVariables = graphics // {
      DISPLAY = ":0";
      WAYLAND_DISPLAY = "wayland-0";
    };
  };
}
