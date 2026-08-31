{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:

stdenvNoCC.mkDerivation {
  pname = "orca-editor";
  version = "1.4.188";

  src = fetchurl {
    url = "https://github.com/stablyai/orca/releases/download/v1.4.188/orca-macos-arm64.dmg";
    hash = "sha256-rC7OdVj2/YkxNcUC6EshYfHGJD2KYuL7lL7G62s7JX4=";
  };

  nativeBuildInputs = [ undmg ];
  dontFixup = true;

  unpackPhase = "undmg $src";
  installPhase = ''
    mkdir -p "$out/Applications" "$out/bin"
    cp -R Orca.app "$out/Applications/"
    ln -s "$out/Applications/Orca.app/Contents/Resources/bin/orca" "$out/bin/orca"
  '';

  meta = {
    description = "The Stably Orca desktop editor";
    homepage = "https://onorca.dev/";
    license = lib.licenses.unfree;
    mainProgram = "orca";
    platforms = [ "aarch64-darwin" ];
  };
}
