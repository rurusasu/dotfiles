{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

stdenvNoCC.mkDerivation {
  pname = "dia-browser";
  version = "1.49.1-87398";

  src = fetchurl {
    url = "https://releases.diabrowser.com/release/Dia-1.49.1-87398.zip";
    hash = "sha256-a5sY+TplIMQODF27eS1jTapvFXKG+OK1nRWwEfcZqf4=";
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
