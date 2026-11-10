{ inputs, pkgs }:
pkgs.stdenvNoCC.mkDerivation {
  name = "steam-darwin";
  src = inputs.steam-darwin;
  nativeBuildInputs = [ pkgs.undmg ];
  dontFixup = true;
  unpackPhase = "undmg $src";
  installPhase = ''
    mkdir -p "$out/Applications"
    cp -R Steam.app "$out/Applications/"
  '';
  meta = {
    description = "Official Steam bootstrap for macOS";
    homepage = "https://store.steampowered.com/about/";
    license = pkgs.lib.licenses.unfree;
    platforms = [ "aarch64-darwin" ];
  };
}
