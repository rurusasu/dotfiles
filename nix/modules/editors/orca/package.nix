{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
  callPackage,
}:
let
  release = {
    version = "1.4.223";
    sources = {
      aarch64-darwin = {
        url = "https://github.com/stablyai/orca/releases/download/v1.4.223/orca-macos-arm64.dmg";
        hash = "sha256-z4mOSjQpW4G+twMNNuT1F08WvDx9skHrW7j0E+gy3LI=";
      };
      x86_64-linux = {
        url = "https://github.com/stablyai/orca/releases/download/v1.4.223/orca-linux.AppImage";
        hash = "sha256-Dhis/lwH7Rk6/2A/tja6H8WQeBEgOad5pUQ6jVNIPUs=";
      };
      aarch64-linux = {
        url = "https://github.com/stablyai/orca/releases/download/v1.4.223/orca-linux-arm64.AppImage";
        hash = "sha256-2n/S5dzTfyWCSA7c+gpLdILXxVXfWYvrrs0nhdTLD0A=";
      };
    };
  };
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
