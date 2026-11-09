{ pkgs, feed }:
let
  inherit (pkgs) lib;
  isDarwin = pkgs.stdenv.hostPlatform.system == "aarch64-darwin";
  version = feed.app.version;
  releaseTag = "v${version}";
  desktopAsset = feed.app.platforms.${if isDarwin then "darwin-aarch64" else "linux-x86_64"};
  controlPlatform = if isDarwin then "macos-arm64" else "linux-x86_64";
  controlAsset =
    lib.findSingle (asset: asset.platform == controlPlatform)
      (throw "Strata feed has no Control asset for ${controlPlatform}")
      (throw "Strata feed has multiple Control assets for ${controlPlatform}")
      feed.control.packages;
  controlVersion = feed.control.version;
  fetchAsset =
    asset:
    pkgs.fetchurl {
      # The desktop URLs in the feed use /latest/download/. Pin every asset to
      # the feed's release so later releases cannot change this derivation.
      url = "https://github.com/Niko1221/Strata/releases/download/${releaseTag}/${builtins.baseNameOf asset.url}";
      inherit (asset) sha256;
    };
  desktopSource = fetchAsset desktopAsset;
  controlSource = fetchAsset controlAsset;
  desktopContents = pkgs.appimageTools.extract {
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
  linuxProfile = profile + ''
    if [ -d /usr/lib/wsl/lib ]; then
      export PATH="/usr/lib/wsl/lib:$PATH"
      export LD_LIBRARY_PATH="/usr/lib/wsl/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    fi
  '';
  # FHS environments replace /usr; keep the Windows-provided CUDA driver
  # and nvidia-smi visible on WSL, without requiring them on native Linux.
  extraBwrapArgs = [ "--ro-bind-try /usr/lib/wsl /usr/lib/wsl" ];
  extraBuildCommands = ''
    # Bubblewrap needs a mount point inside the read-only /usr tree.
    mkdir -p "$out/usr/lib64/wsl"
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
    inherit version extraBwrapArgs extraBuildCommands;
    profile = linuxProfile;
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
    inherit extraBwrapArgs extraBuildCommands;
    profile = linuxProfile;
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
