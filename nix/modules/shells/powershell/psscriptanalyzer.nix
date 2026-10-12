{
  lib,
  stdenvNoCC,
  src,
  unzip,
}:
stdenvNoCC.mkDerivation {
  name = "psscriptanalyzer";
  # The version-free Gallery input is refreshed by nix flake update.
  # flake.lock records its content hash; no runtime download is needed.
  inherit src;

  nativeBuildInputs = [ unzip ];
  dontUnpack = true;
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/powershell/Modules/PSScriptAnalyzer"
    unzip -q "$src" -d "$out/share/powershell/Modules/PSScriptAnalyzer"
    runHook postInstall
  '';

  meta = {
    description = "PowerShell formatter and static analyzer module";
    homepage = "https://github.com/PowerShell/PSScriptAnalyzer";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
