{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
  appimageTools,
  makeWrapper,
}:
let
  release = {
    version = "1.1.7";
    sources = {
      aarch64-darwin = {
        url = "https://download.todesktop.com/241012ess7yxs0e/Comfy%20Desktop%201.1.7%20-%20Build%20261013p26tnl6re-arm64-mac.zip";
        hash = "sha256-b5JOfHpQFmg5WZu0DbGXyWyUVNn9C4Vfo8H9CEqpbmc=";
      };
      x86_64-linux = {
        url = "https://download.todesktop.com/241130tqe9q3y/comfyui-desktop-2-1.1.7-build-261013p26tnl6re-x86_64.AppImage";
        hash = "sha256-hfymSmZ2TERdM1xMJbbkS3gaZ1oAr5rpW46wJoOaQGI=";
      };
    };
  };
  system = stdenvNoCC.hostPlatform.system;
  source = release.sources.${system} or (throw "ComfyUI Desktop does not support ${system}");
  pname = "comfyui-desktop";
  inherit (release) version;
  src = fetchurl source;
  meta = {
    description = "Official desktop application for installing and running ComfyUI";
    homepage = "https://github.com/Comfy-Org/Comfy-Desktop";
    license = lib.licenses.agpl3Plus;
    mainProgram = pname;
    platforms = [
      "aarch64-darwin"
      "x86_64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
in
if stdenvNoCC.hostPlatform.isLinux then
  let
    contents = appimageTools.extract { inherit pname version src; };
  in
  appimageTools.wrapType2 {
    inherit
      pname
      version
      src
      meta
      ;
    nativeBuildInputs = [ makeWrapper ];
    extraInstallCommands = ''
      # Match the upstream Linux launcher inside the AppImage's FHS environment.
      # Nix owns application updates; do not inherit another AppImage's path.
      wrapProgram "$out/bin/${pname}" --unset APPIMAGE --add-flags --no-sandbox
      install -Dm644 ${contents}/comfyui-desktop-2.desktop \
        "$out/share/applications/comfyui-desktop.desktop"
      substituteInPlace "$out/share/applications/comfyui-desktop.desktop" \
        --replace-fail 'Exec=AppRun --no-sandbox' "Exec=$out/bin/${pname}"
      mkdir -p "$out/share/icons"
      cp -r ${contents}/usr/share/icons/hicolor "$out/share/icons/"
      test -x ${contents}/resources/bootstrap-python/bin/python3
    '';
  }
else
  stdenvNoCC.mkDerivation {
    inherit
      pname
      version
      src
      meta
      ;
    nativeBuildInputs = [ unzip ];
    dontConfigure = true;
    dontBuild = true;
    # Preserve the vendor's signed app and bundled Python runtime.
    dontFixup = true;
    unpackPhase = ''
      runHook preUnpack
      unzip -qq "$src"
      runHook postUnpack
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/Applications" "$out/bin"
      mv "Comfy Desktop.app" "$out/Applications/"
      ln -s "$out/Applications/Comfy Desktop.app/Contents/MacOS/Comfy Desktop" \
        "$out/bin/${pname}"
      test -x "$out/bin/${pname}"
      test -x "$out/Applications/Comfy Desktop.app/Contents/Resources/bootstrap-python/bin/python3"
      runHook postInstall
    '';
  }
