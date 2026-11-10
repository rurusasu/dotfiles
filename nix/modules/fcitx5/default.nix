{
  config,
  lib,
  pkgs,
  platform,
  ...
}:
let
  cfg = config.i18n.inputMethod.fcitx5;
in
{
  options.i18n.inputMethod.fcitx5.wslIntegration.enable =
    lib.mkEnableOption "WSLg input method startup and display integration";

  config = lib.mkMerge [
    {
      i18n.inputMethod.enable = lib.mkIf pkgs.stdenv.hostPlatform.isLinux true;
      i18n.inputMethod.fcitx5.wslIntegration.enable = platform == "wsl";
    }
    (lib.mkIf config.i18n.inputMethod.enable {
      i18n.inputMethod = {
        type = "fcitx5";
        fcitx5 = {
          addons = [ pkgs.fcitx5-mozc ];
          waylandFrontend = lib.mkIf cfg.wslIntegration.enable false;
          settings.inputMethod = {
            "Groups/0" = {
              Name = "Default";
              "Default Layout" = "us";
              DefaultIM = "mozc";
            };
            "Groups/0/Items/0".Name = "keyboard-us";
            "Groups/0/Items/1".Name = "mozc";
            GroupOrder."0" = "Default";
          };
        };
      };
      xdg.configFile = {
        # Restore the declared profile after fcitx5 replaces it on exit.
        fcitx5 = {
          recursive = true;
          force = true;
        };
      };
      # Generate the override; systemd owns startup because WSLg disables Wayland.
      xdg.autostart = lib.mkIf (cfg.wslIntegration.enable && cfg.systemd.enable) {
        enable = true;
        entries = [
          "${
            pkgs.makeDesktopItem {
              name = "org.fcitx.Fcitx5";
              desktopName = "Fcitx 5";
              extraConfig.Hidden = "true";
            }
          }/share/applications/org.fcitx.Fcitx5.desktop"
        ];
      };
      systemd.user.services.fcitx5-daemon = lib.mkIf (cfg.wslIntegration.enable && cfg.systemd.enable) {
        Unit.After = [ "basic.target" ];
        Service = {
          ExecStart = lib.mkForce "${config.i18n.inputMethod.package}/bin/fcitx5 --disable=wayland";
          Restart = "on-failure";
          Environment = [
            "DISPLAY=:0"
            "WAYLAND_DISPLAY="
          ];
        };
        Install.WantedBy = lib.mkForce [ "default.target" ];
      };
    })
  ];
}
