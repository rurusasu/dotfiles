{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:
let
  release = builtins.fromJSON (builtins.readFile ./sources.json);
  package = stdenvNoCC.mkDerivation {
    pname = "hermes-agent-bundled";
    inherit (release) version;
    src = fetchurl release.source;

    nativeBuildInputs = [ unzip ];
    dontConfigure = true;
    dontBuild = true;
    # Preserve the vendor's signed app, nested binaries and relative launchers.
    dontFixup = true;

    unpackPhase = ''
      runHook preUnpack
      unzip -qq "$src"
      runHook postUnpack
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/Applications" "$out/bin"
      mv "Hermes Agent.app" "$out/Applications/"
      for command in hermes hermes-agent hermes-acp; do
        ln -s "$out/Applications/Hermes Agent.app/Contents/Resources/agent-payload/bin/$command" "$out/bin/$command"
      done
      cat > "$out/bin/hermes-desktop" <<EOF
      #!${stdenvNoCC.shell}
      exec "$out/Applications/Hermes Agent.app/Contents/MacOS/Hermes Agent" "\$@"
      EOF
      chmod +x "$out/bin/hermes-desktop"
      runHook postInstall
    '';

    passthru = {
      inherit payload;
      python = "${payload}/tools/python-${release.python}-darwin-arm64/bin/python3";
      sitePackages = "${payload}/venv/lib/python3.14/site-packages";
      hermesSource = "${payload}/hermes-agent";
    };
    meta = {
      description = "Hermes Agent with the official bundled desktop and Python runtime";
      homepage = "https://hermes-agent.nousresearch.com/";
      license = lib.licenses.mit;
      mainProgram = "hermes";
      platforms = [ "aarch64-darwin" ];
    };
  };
  payload = "${package}/Applications/Hermes Agent.app/Contents/Resources/agent-payload";
in
package
