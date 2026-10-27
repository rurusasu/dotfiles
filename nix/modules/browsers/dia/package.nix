{ inputs, pkgs }:
pkgs.stdenvNoCC.mkDerivation {
  name = "dia-browser";
  src = inputs.dia;

  nativeBuildInputs = [ pkgs.undmg ];
  dontFixup = true;

  unpackPhase = "undmg $src";
  installPhase = ''
    mkdir -p "$out/Applications"
    cp -R Dia.app "$out/Applications/"
  '';

  meta = {
    description = "The Dia web browser";
    homepage = "https://www.diabrowser.com/";
    license = pkgs.lib.licenses.unfree;
    mainProgram = "Dia";
    platforms = [ "aarch64-darwin" ];
  };
}
