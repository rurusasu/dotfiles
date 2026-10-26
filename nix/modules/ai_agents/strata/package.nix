{ pkgs, release }:
let
  inherit (pkgs) lib;
  version = lib.removePrefix "v" release.tag_name;
  selectAsset =
    description: predicate:
    lib.findSingle predicate (throw "Strata release has no ${description} asset")
      (throw "Strata release has multiple ${description} assets")
      release.assets;
  desktopAsset = selectAsset "Linux x86_64 desktop" (
    asset: asset.name == "Strata-${version}-linux-x86_64.AppImage"
  );
  controlPattern = "strata-control-(.+)-linux-x86_64[.]tar[.]gz";
  controlAsset = selectAsset "Linux x86_64 Control" (
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
        tar -xzf ${controlSource} -C "$out"
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
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
  desktop = pkgs.appimageTools.wrapAppImage {
    pname = "strata-desktop";
    inherit version profile;
    src = desktopSource;
    contents = desktopContents;
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
  control = pkgs.buildFHSEnv {
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
{
  inherit desktop control;
}
