{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

stdenvNoCC.mkDerivation {
  pname = "dia-browser";
  version = "1.45.2-85817";

  src = fetchurl {
    url = "https://releases.diabrowser.com/release/Dia-1.45.2-85817.zip";
    hash = "sha256-xlbeV+uT2qS4mI6Of+1wHC9VEXqT0qssyaQ49nL/TBI=";
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
