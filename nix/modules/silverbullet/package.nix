{ pkgs }:
pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "silverbullet-desktop";
  version = "2.12.1";

  src = pkgs.fetchurl {
    url = "https://release.silverbullet.md/electron/artifacts/${finalAttrs.version}/mac/arm64/SilverBullet-${finalAttrs.version}-mac-arm64.dmg";
    hash = "sha256-iQ0PzVFJleMIONNURMMKJlvR6wcPLF6I+wULSpqxMG4=";
  };

  nativeBuildInputs = [ pkgs.undmg ];
  dontFixup = true;
  unpackPhase = "undmg $src";
  installPhase = ''
    mkdir -p "$out/Applications"
    cp -R SilverBullet.app "$out/Applications/"
  '';

  meta = {
    description = "SilverBullet desktop application";
    homepage = "https://silverbullet.md/desktop";
    license = pkgs.lib.licenses.unfree;
    platforms = [ "aarch64-darwin" ];
  };
})
