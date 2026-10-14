# Japanese proportional fallbacks for WSLg; retain the existing primary fonts.
{ lib, pkgs }:
{
  packages = [
    pkgs.noto-fonts-cjk-sans
    pkgs.noto-fonts-cjk-serif
  ];

  fontconfig.defaultFonts = {
    sansSerif = lib.mkAfter [ "Noto Sans CJK JP" ];
    serif = lib.mkAfter [ "Noto Serif CJK JP" ];
  };
}
