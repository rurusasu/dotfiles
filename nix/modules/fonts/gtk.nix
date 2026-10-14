{ lib, pkgs, ... }:
lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
  # GTK settings also feed the desktop portal used by Wayland applications.
  gtk = {
    enable = true;
    font = {
      name = "UDEV Gothic NF";
      size = 11;
    };
  };
}
