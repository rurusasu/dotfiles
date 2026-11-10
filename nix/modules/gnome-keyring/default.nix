{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkMerge [
    { services.gnome-keyring.enable = lib.mkIf pkgs.stdenv.hostPlatform.isLinux true; }
    (lib.mkIf config.services.gnome-keyring.enable {
      # WSL has no desktop login to start this user service.
      services.gnome-keyring = {
        components = [ "secrets" ];
      };
      systemd.user.services.gnome-keyring = {
        Unit.After = [ "basic.target" ];
        Install.WantedBy = lib.mkForce [ "default.target" ];
      };
    })
  ];
}
