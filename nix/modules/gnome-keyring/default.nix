{ config, lib, ... }:
{
  config = lib.mkIf config.services.gnome-keyring.enable {
    # WSL has no desktop login to start this user service.
    services.gnome-keyring = {
      components = [ "secrets" ];
    };
    systemd.user.services.gnome-keyring = {
      Unit.After = [ "basic.target" ];
      Install.WantedBy = lib.mkForce [ "default.target" ];
    };
  };
}
