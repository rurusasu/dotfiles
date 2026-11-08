{ pkgs }:
let
  tag = pkgs.lib.removeSuffix "\n" (builtins.readFile /mnt/d/lifelog-core/.git/lifelog-release-tag);
  stableSemver = "v(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)";
  source = builtins.fetchGit {
    url = "/mnt/d/lifelog-core";
    ref =
      if builtins.match stableSemver tag != null then
        "refs/tags/${tag}"
      else
        throw "Lifelog release tag must be a stable SemVer tag, such as v1.2.3";
  };
  manifest = builtins.fromTOML (builtins.readFile "${source}/Cargo.toml");
  guiLibraries = with pkgs; [
    dbus
    wayland
    libxkbcommon
    libx11
    libxcursor
    libxi
    libxrandr
    libxrender
    libxfixes
    fontconfig
    freetype
    libGL
    vulkan-loader
  ];
in
pkgs.rustPlatform.buildRustPackage {
  pname = "lifelog";
  version =
    if "v${manifest.package.version}" == tag then
      manifest.package.version
    else
      throw "Lifelog Cargo.toml version does not match the selected release tag";
  src = source;
  cargoLock.lockFile = "${source}/Cargo.lock";
  nativeBuildInputs = with pkgs; [
    pkg-config
    makeWrapper
  ];
  buildInputs = guiLibraries;
  # The application repository runs its tests in CI.
  doCheck = false;
  postInstall = ''
    wrapProgram "$out/bin/lifelog" \
      --prefix LD_LIBRARY_PATH : "/run/opengl-driver/lib:/usr/lib/wsl/lib:${pkgs.lib.makeLibraryPath guiLibraries}"
  '';
  meta = {
    description = "Local-first file workspace";
    mainProgram = "lifelog";
    platforms = [ "x86_64-linux" ];
    license = pkgs.lib.licenses.mit;
  };
}
