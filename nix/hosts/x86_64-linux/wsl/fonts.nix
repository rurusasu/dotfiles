# WSLg's compositor reads fonts through the mounted user distro's /usr/local.
# Copy real files: absolute Nix store symlinks cannot resolve in its namespace.
{ pkgs, ... }:
let
  fontDirectory = "/usr/local/share/fonts/dotfiles-wslg";
  fontFile = "NotoSansCJK-VF.otf.ttc";
  sourceFont = "${pkgs.noto-fonts-cjk-sans}/share/fonts/opentype/noto-cjk/${fontFile}";
in
{
  # An already running Weston retains its Pango font map until WSLg restarts.
  # Keep active GUI applications running; this only prepares persistent fonts.
  system.activationScripts.wslgFonts = {
    deps = [ "specialfs" ];
    text = ''
      ${pkgs.coreutils}/bin/install -d -m 0755 ${fontDirectory}
      ${pkgs.coreutils}/bin/install --compare -m 0644 ${sourceFont} ${fontDirectory}/${fontFile}
    '';
  };
}
