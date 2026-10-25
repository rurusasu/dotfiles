{ lib, ... }:
{
  # WSL has no desktop login to start this user service.
  services.gnome-keyring = {
    enable = true;
    components = [ "secrets" ];
  };
  systemd.user.services.gnome-keyring = {
    Unit.After = [ "basic.target" ];
    Install.WantedBy = lib.mkForce [ "default.target" ];
  };
}
