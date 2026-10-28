{ pkgs, release }:
let
  inherit (pkgs) lib;
  isDarwin = pkgs.stdenv.hostPlatform.system == "aarch64-darwin";
  version = lib.removePrefix "v" release.tag_name;
  selectAsset =
    description: predicate:
    lib.findSingle predicate (throw "Strata release has no ${description} asset")
      (throw "Strata release has multiple ${description} assets")
      release.assets;
  desktopAsset = selectAsset "desktop for ${pkgs.stdenv.hostPlatform.system}" (
    asset:
    asset.name == (if isDarwin then "Strata.app.tar.gz" else "Strata-${version}-linux-x86_64.AppImage")
  );
  controlPattern = "strata-control-(.+)-${
    if isDarwin then "macos-arm64" else "linux-x86_64"
  }[.]tar[.]gz";
  controlAsset = selectAsset "Control for ${pkgs.stdenv.hostPlatform.system}" (
    asset: builtins.match controlPattern asset.name != null
  );
  controlVersion = builtins.head (builtins.match controlPattern controlAsset.name);
  fetchAsset =
    asset:
    let
      digest = asset.digest or null;
    in
    if !builtins.isString digest || builtins.match "sha256:[0-9a-fA-F]{64}" digest == null then
      throw "Strata release asset ${asset.name} has no valid SHA-256 digest"
    else
      pkgs.fetchurl {
        url = asset.browser_download_url;
        sha256 = lib.removePrefix "sha256:" digest;
      };
  desktopSource = fetchAsset desktopAsset;
  controlSource = fetchAsset controlAsset;
  desktopContents = pkgs.appimageTools.extractType2 {
    pname = "strata-desktop";
    inherit version;
    src = desktopSource;
    postExtract = ''
      # The Terminal already honors this upstream switch. Make the desktop's
      # independent Control selection follow the same immutable package too.
      substituteInPlace "$out/usr/lib/Strata/host/server/control-runtime.mjs" \
        --replace-fail \
          'const updated = updatedControlDirectory({ env, platform, components });' \
          'const updated = env.STRATA_NO_HANDOVER ? null : updatedControlDirectory({ env, platform, components });'
    '';
  };
  controlContents =
    pkgs.runCommand "strata-control-${controlVersion}-contents"
      {
        nativeBuildInputs = [
          pkgs.gnutar
          pkgs.gzip
        ];
      }
      ''
        mkdir -p "$out"
        tar --warning=no-unknown-keyword -xzf ${controlSource} -C "$out"
        test -x "$out/bin/strata"
        test -x "$out/python/bin/python3"
        test "$(cat "$out/VERSION")" = ${lib.escapeShellArg controlVersion}
      '';
  profile = ''
    export STRATA_NO_HANDOVER=1
    export PYTHONDONTWRITEBYTECODE=1
  '';
  meta = {
    homepage = "https://github.com/Niko1221/Strata";
    license = lib.licenses.mit;
    platforms = [ pkgs.stdenv.hostPlatform.system ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
  desktop = if isDarwin then darwinDesktop else linuxDesktop;
  control = if isDarwin then darwinControl else linuxControl;
  darwinDesktop = pkgs.stdenvNoCC.mkDerivation {
    pname = "strata-desktop";
    inherit version;
    src = desktopSource;
    sourceRoot = "Strata.app";
    nativeBuildInputs = [ pkgs.makeWrapper ];
    dontFixup = true;
    preUnpack = ''
      export TAR_OPTIONS=--warning=no-unknown-keyword
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/Applications" "$out/bin"
      cp -R . "$out/Applications/Strata.app"
      makeWrapper "$out/Applications/Strata.app/Contents/MacOS/strata-desktop" \
        "$out/bin/strata-desktop" \
        --set STRATA_NO_HANDOVER 1 \
        --set PYTHONDONTWRITEBYTECODE 1
      runHook postInstall
    '';
    passthru = {
      releaseTag = release.tag_name;
    };
    meta = meta // {
      description = "Strata local AI desktop application";
      mainProgram = "strata-desktop";
    };
  };
  darwinControl =
    pkgs.runCommand "strata-control-${controlVersion}"
      {
        version = controlVersion;
        nativeBuildInputs = [ pkgs.makeWrapper ];
        passthru = {
          inherit controlContents;
          productVersion = version;
          releaseTag = release.tag_name;
        };
        meta = meta // {
          description = "Strata Terminal with its bundled Python and Control runtime";
          mainProgram = "strata";
        };
      }
      ''
        mkdir -p "$out/bin"
        makeWrapper ${controlContents}/bin/strata "$out/bin/strata" \
          --set STRATA_NO_HANDOVER 1 \
          --set PYTHONDONTWRITEBYTECODE 1
      '';
  linuxDesktop = pkgs.appimageTools.wrapAppImage {
    pname = "strata-desktop";
    inherit version profile;
    src = desktopSource;
    contents = desktopContents;
    # The bundled libgcrypt needs this library from the host environment.
    extraPkgs = packages: [ packages.libgpg-error ];
    extraInstallCommands = ''
      install -Dm444 ${desktopContents}/Strata.desktop \
        "$out/share/applications/Strata.desktop"
      install -Dm444 ${desktopContents}/Strata.png \
        "$out/share/pixmaps/strata-desktop.png"
    '';
    passthru = {
      inherit desktopContents;
      releaseTag = release.tag_name;
    };
    meta = meta // {
      description = "Strata local AI desktop application";
      mainProgram = "strata-desktop";
    };
  };
  linuxControl = pkgs.buildFHSEnv {
    pname = "strata-control";
    version = controlVersion;
    executableName = "strata";
    inherit profile;
    targetPkgs = packages: [
      packages.bash
      packages.coreutils
      packages.stdenv.cc.cc.lib
      packages.zlib
      packages.openssl
      packages.libffi
      packages.xz
      packages.bzip2
      packages.libxcrypt-legacy
    ];
    runScript = "${controlContents}/bin/strata";
    passthru = {
      inherit controlContents;
      productVersion = version;
      releaseTag = release.tag_name;
    };
    meta = meta // {
      description = "Strata Terminal with its bundled Python and Control runtime";
      mainProgram = "strata";
    };
  };
in
assert lib.assertMsg (builtins.elem pkgs.stdenv.hostPlatform.system [
  "x86_64-linux"
  "aarch64-darwin"
]) "Strata packages require x86_64-linux or aarch64-darwin.";
{
  inherit desktop control;
}
