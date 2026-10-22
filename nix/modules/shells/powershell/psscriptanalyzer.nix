{
  lib,
  stdenvNoCC,
  src,
  unzip,
}:
stdenvNoCC.mkDerivation {
  name = "psscriptanalyzer";
  # The flake input selects an upstream release asset and records its content
  # hash in flake.lock; no runtime download is needed.
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
