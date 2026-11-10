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
  config = lib.mkMerge [
    { dotfiles.fonts.enable = true; }
    (lib.mkIf config.dotfiles.fonts.enable {
      fonts.fontconfig = sharedFonts.fontconfig;

      # Integrated NixOS/nix-darwin install system fonts; standalone profiles use
      # Home Manager's native font handling from home.packages.
      home.packages = lib.optionals (!config.submoduleSupport.enable) sharedFonts.packages;

      # GTK settings also feed the desktop portal used by Wayland applications.
      gtk = {
        theme = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
          name = "catppuccin-${config.catppuccin.flavor}-${config.catppuccin.accent}-standard+default";
          package = pkgs.catppuccin-gtk.override {
            variant = config.catppuccin.flavor;
            accents = [ config.catppuccin.accent ];
          };
        };
        gtk4.theme = lib.mkIf pkgs.stdenv.hostPlatform.isLinux config.gtk.theme;

        enable = pkgs.stdenv.hostPlatform.isLinux;
        font = {
          name = builtins.head config.fonts.fontconfig.defaultFonts.monospace;
          size = 11;
        };
      };
    })
  ];
}
