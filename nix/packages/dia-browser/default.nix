{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

stdenvNoCC.mkDerivation {
  pname = "dia-browser";
  version = "1.48.0-86796";

  src = fetchurl {
    url = "https://releases.diabrowser.com/release/Dia-1.48.0-86796.zip";
    hash = "sha256-6EhVLvviaeTKvlbKe5fpY6VVdqEGt01X+2F4Yzd5Fb0=";
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
