{
  lib,
  fetchurl,
  appimageTools,
  buildFHSEnv,
  source,
  version,
}:
let
  pname = "orca-editor";
  src = fetchurl source;
  contents = appimageTools.extract { inherit pname version src; };
  extraPkgs = pkgs: [
    (pkgs.python3.withPackages (pythonPackages: [ pythonPackages.pygobject3 ]))
    pkgs.at-spi2-core
    pkgs.xdotool
    pkgs.xclip
    pkgs.xorg-server
  ];
  # Use the vendor CLI in the same FHS environment as the AppImage GUI.
  # Linux deliberately names it orca-ide to avoid the GNOME Orca screen reader.
  cli = buildFHSEnv (
    appimageTools.defaultFhsEnvArgs
    // {
      pname = "orca-ide";
      inherit version;
      targetPkgs = pkgs: appimageTools.defaultFhsEnvArgs.targetPkgs pkgs ++ extraPkgs pkgs;
      runScript = "${contents}/resources/bin/orca-ide";
    }
  );
in
appimageTools.wrapType2 {
  inherit
    pname
    version
    src
    extraPkgs
    ;
  extraInstallCommands = ''
    test -x ${contents}/resources/bin/orca-ide
    ln -s ${cli}/bin/orca-ide $out/bin/orca-ide
    install -Dm644 ${contents}/orca-ide.desktop $out/share/applications/orca-ide.desktop
    substituteInPlace $out/share/applications/orca-ide.desktop \
      --replace-fail 'Exec=AppRun' "Exec=$out/bin/orca-editor"
    mkdir -p $out/share/icons
    cp -r ${contents}/usr/share/icons/hicolor $out/share/icons/
  '';
  meta = {
    description = "The Stably Orca desktop editor";
    homepage = "https://onorca.dev/";
    license = lib.licenses.unfree;
    mainProgram = "orca-ide";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
