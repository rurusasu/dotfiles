{
  config,
  lib,
  pkgs,
  ...
}:
let
  sharedFonts = (import ./settings.nix { inherit pkgs; }).fonts;
in
{
  options.dotfiles.fonts.enable = lib.mkEnableOption "managed fonts and desktop font preferences";
  config = lib.mkIf config.dotfiles.fonts.enable {
    fonts.fontconfig = sharedFonts.fontconfig;

    # Integrated NixOS/nix-darwin install system fonts; standalone profiles use
    # Home Manager's native font handling from home.packages.
    home.packages = lib.optionals (!config.submoduleSupport.enable) sharedFonts.packages;

    # GTK settings also feed the desktop portal used by Wayland applications.
    gtk = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      enable = true;
      font = {
        name = "UDEV Gothic NF";
        size = 11;
      };
    };
  };
}
