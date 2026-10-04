{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

stdenvNoCC.mkDerivation {
  pname = "dia-browser";
  version = "1.51.1-88214";

  src = fetchurl {
    url = "https://releases.diabrowser.com/release/Dia-1.51.1-88214.zip";
    hash = "sha256-iOLoxbL7j88LANT4eb0BsYm4pW0Nh2FWLDc3yk4A4JM=";
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
