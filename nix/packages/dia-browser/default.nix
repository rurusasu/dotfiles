{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

stdenvNoCC.mkDerivation {
  pname = "dia-browser";
  version = "1.52.0-88431";

  src = fetchurl {
    url = "https://releases.diabrowser.com/release/Dia-1.52.0-88431.zip";
    hash = "sha256-2M4G6MJ4FyGiwtq78YsnPBmHe8lyMiRDgoVkFY/MrdI=";
  };

  nativeBuildInputs = [ unzip ];
  dontFixup = true;

  unpackPhase = "unzip $src";
  installPhase = ''
    mkdir -p "$out/Applications"
    cp -R Dia.app "$out/Applications/"
  '';

  meta = {
    description = "The Dia web browser";
    homepage = "https://www.diabrowser.com/";
    license = lib.licenses.unfree;
    mainProgram = "Dia";
    platforms = [ "aarch64-darwin" ];
  };
}
