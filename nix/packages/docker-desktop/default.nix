{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:

stdenvNoCC.mkDerivation {
  pname = "docker-desktop";
  version = "4.88.1-237512";

  src = fetchurl {
    url = "https://desktop.docker.com/mac/main/arm64/237512/Docker.dmg";
    hash = "sha256-lBAtT+BWvzpP3jddaTqulqQpFX2tA0WvmFPXFX1r1b0=";
  };

  nativeBuildInputs = [ undmg ];
  dontFixup = true;

  unpackPhase = "undmg $src";
  installPhase = ''
    mkdir -p "$out/Applications" "$out/bin" "$out/libexec/docker/cli-plugins"
    cp -R Docker.app "$out/Applications/"
    for command in docker docker-compose docker-credential-desktop docker-credential-osxkeychain; do
      if [ -e "$out/Applications/Docker.app/Contents/Resources/bin/$command" ]; then
        ln -s "$out/Applications/Docker.app/Contents/Resources/bin/$command" "$out/bin/$command"
      fi
    done
    if [ -e "$out/Applications/Docker.app/Contents/Resources/cli-plugins/docker-buildx" ]; then
      ln -s "$out/Applications/Docker.app/Contents/Resources/cli-plugins/docker-buildx" \
        "$out/libexec/docker/cli-plugins/docker-buildx"
    fi
    if [ -e "$out/Applications/Docker.app/Contents/Resources/cli-plugins/docker-compose" ]; then
      ln -s "$out/Applications/Docker.app/Contents/Resources/cli-plugins/docker-compose" \
        "$out/libexec/docker/cli-plugins/docker-compose"
    fi
  '';

  meta = {
    description = "Docker Desktop for Apple Silicon macOS";
    homepage = "https://www.docker.com/products/docker-desktop/";
    license = lib.licenses.unfree;
    platforms = [ "aarch64-darwin" ];
  };
}
