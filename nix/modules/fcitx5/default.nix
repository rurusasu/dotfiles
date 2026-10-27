{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.i18n.inputMethod.enable {
    i18n.inputMethod = {
      type = "fcitx5";
      fcitx5 = {
        addons = [ pkgs.fcitx5-mozc ];
        waylandFrontend = false;
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
      # systemd owns startup because WSLg needs the Wayland addon disabled.
      "autostart/org.fcitx.Fcitx5.desktop".text = ''
        [Desktop Entry]
        Hidden=true
      '';
    };
    systemd.user.services.fcitx5-daemon = {
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
  };
}
