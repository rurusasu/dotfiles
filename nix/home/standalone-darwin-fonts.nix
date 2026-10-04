{ pkgs, lib, ... }:
let
  inherit ((import ../modules/fonts.nix { inherit pkgs; })) fonts;
  fontFiles = lib.concatMapStringsSep "\n" (font: ''
    ${pkgs.findutils}/bin/find "${font}/share/fonts" -type f \( -name '*.ttf' -o -name '*.otf' \) -print |
      while IFS= read -r fontPath; do
        fontName="$(basename "$fontPath")"
        run cp -f "$fontPath" "$fontTarget/$fontName"
      done
  '') fonts.packages;
in
{
  home.packages = fonts.packages;
  fonts.fontconfig = fonts.fontconfig;

  home.activation.installDotfilesFonts = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    fontTarget="$HOME/Library/Fonts"
    run mkdir -p "$fontTarget"
    ${fontFiles}
  '';
}
