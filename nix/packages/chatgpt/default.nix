{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  dpkg,
  makeWrapper,
  alsa-lib,
  at-spi2-atk,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  gdk-pixbuf,
  glib,
  gtk3,
  libGL,
  libX11,
  libXcomposite,
  libXdamage,
  libXext,
  libXfixes,
  libXrandr,
  libdrm,
  libgbm,
  libnotify,
  libusb1,
  libxcb,
  libxkbcommon,
  mesa,
  nspr,
  nss,
  pango,
  pulseaudio,
  systemd,
}:
let
  version = "26.818.41705";
  sources = {
    x86_64-linux = {
      url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_amd64.deb";
      hash = "sha256-ySfJhVd73luszsx38C4UsxHZTmIwFWYh+vkleawDalU=";
    };
    aarch64-linux = {
      url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_arm64.deb";
      hash = "sha256-Y3WtHooJT3Z5HiC58xyIhxnOz6E/Ct0sS7yAlgb3NIE=";
    };
  };
  source =
    sources.${stdenv.hostPlatform.system}
      or (throw "ChatGPT is unsupported on ${stdenv.hostPlatform.system}");
  runtimeDependencies = [
    alsa-lib
    at-spi2-atk
    atk
    cairo
    cups
    dbus
    expat
    gdk-pixbuf
    glib
    gtk3
    libGL
    libX11
    libXcomposite
    libXdamage
    libXext
    libXfixes
    libXrandr
    libdrm
    libgbm
    libnotify
    libusb1
    libxcb
    libxkbcommon
    mesa
    nspr
    nss
    pango
    pulseaudio
    systemd
  ];
in
stdenv.mkDerivation {
  pname = "chatgpt";
  inherit version;
  src = fetchurl source;

  nativeBuildInputs = [
    autoPatchelfHook
    dpkg
    makeWrapper
  ];
  buildInputs = runtimeDependencies;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    dpkg-deb --extract "$src" "$out"
    mkdir -p "$out/bin"
    makeWrapper "$out/usr/lib/chatgpt/ChatGPT" "$out/bin/chatgpt" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeDependencies}"
    runHook postInstall
  '';

  meta = {
    description = "Official ChatGPT desktop application for Linux";
    homepage = "https://learn.chatgpt.com/docs/linux/linux-app";
    license = lib.licenses.unfree;
    mainProgram = "chatgpt";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
