{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
  callPackage,
}:
let
  release = builtins.fromJSON (builtins.readFile ./sources.json);
  system = stdenvNoCC.hostPlatform.system;
  source = release.sources.${system} or (throw "Orca Editor does not support ${system}");
in
if stdenvNoCC.hostPlatform.isLinux then
  callPackage ./linux.nix {
    inherit source;
    inherit (release) version;
  }
else
  stdenvNoCC.mkDerivation {
    pname = "orca-editor";
    inherit (release) version;
    src = fetchurl source;

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
