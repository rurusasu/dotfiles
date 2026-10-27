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
  options.dotfiles.fonts.enable = lib.mkEnableOption "system fonts and font preferences";
  config = lib.mkIf config.dotfiles.fonts.enable {
    fonts.packages = sharedFonts.packages;
  };
}
