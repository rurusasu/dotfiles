{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

stdenvNoCC.mkDerivation {
  pname = "hammerspoon";
  version = "1.1.1";

  src = fetchurl {
    url = "https://github.com/Hammerspoon/hammerspoon/releases/download/1.1.1/Hammerspoon-1.1.1.zip";
    hash = "sha256-EbsckPr1Qn83x71P5+q5d0rkPh1csCDFswiNrDKEnvo=";
  };

  nativeBuildInputs = [ unzip ];
  dontFixup = true;

  unpackPhase = "unzip $src";
  installPhase = ''
    mkdir -p "$out/Applications" "$out/bin"
    cp -R Hammerspoon.app "$out/Applications/"
    ln -s "$out/Applications/Hammerspoon.app/Contents/Frameworks/hs/hs" "$out/bin/hs"
  '';

  meta = {
    description = "A desktop automation tool for macOS";
    homepage = "https://www.hammerspoon.org/";
    license = lib.licenses.unfree;
    mainProgram = "hs";
    platforms = [ "aarch64-darwin" ];
  };
}
