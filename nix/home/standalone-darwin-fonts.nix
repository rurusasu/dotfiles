{ pkgs, lib, ... }:
let
  sets = import ../packages/sets.nix {
    inherit pkgs lib;
  };
  fontFiles = lib.concatMapStringsSep "\n" (font: ''
    ${pkgs.findutils}/bin/find "${font}/share/fonts" -type f \( -name '*.ttf' -o -name '*.otf' \) -print |
      while IFS= read -r fontPath; do
        fontName="$(basename "$fontPath")"
        run cp -f "$fontPath" "$fontTarget/$fontName"
      done
  '') sets.fonts;
in
{
  home.packages = sets.fonts;

  home.activation.installDotfilesFonts = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    fontTarget="$HOME/Library/Fonts"
    run mkdir -p "$fontTarget"
    ${fontFiles}
  '';
}
