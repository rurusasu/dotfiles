{ pkgs, ... }:
{
  fonts.packages = [
    pkgs.udev-gothic-nf
    pkgs.noto-fonts-color-emoji
  ];

  fonts.fontconfig = {
    enable = true;
    defaultFonts = {
      monospace = [ "UDEV Gothic NF" ];
      sansSerif = [ "UDEV Gothic NF" ];
      serif = [ "UDEV Gothic NF" ];
      emoji = [ "Noto Color Emoji" ];
    };
  };
}
