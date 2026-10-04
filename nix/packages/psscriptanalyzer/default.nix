{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:
stdenvNoCC.mkDerivation rec {
  pname = "psscriptanalyzer";
  version = "1.22.0";

  # Official immutable release archive; no PowerShell Gallery access at runtime.
  src = fetchurl {
    url = "https://github.com/PowerShell/PSScriptAnalyzer/releases/download/${version}/PSScriptAnalyzer.${version}.nupkg";
    hash = "sha256-cb+561jhnUtmL0SUp9VypyS2DgWIhI3P80GVoOCK4b4=";
  };

  nativeBuildInputs = [ unzip ];
  dontUnpack = true;
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/powershell/Modules/PSScriptAnalyzer/${version}"
    unzip -q "$src" -d "$out/share/powershell/Modules/PSScriptAnalyzer/${version}"
    runHook postInstall
  '';

  meta = {
    description = "PowerShell formatter and static analyzer module";
    homepage = "https://github.com/PowerShell/PSScriptAnalyzer";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
