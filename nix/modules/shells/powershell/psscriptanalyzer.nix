{
  lib,
  stdenvNoCC,
  fetchurl,
  releaseMetadata,
  unzip,
}:
let
  release = builtins.fromJSON (builtins.readFile releaseMetadata);
  version = lib.removePrefix "v" release.tag_name;
  asset =
    lib.findSingle (asset: asset.name == "PSScriptAnalyzer.${version}.nupkg")
      (throw "PSScriptAnalyzer release has no matching NuGet package")
      (throw "PSScriptAnalyzer release has multiple matching NuGet packages")
      release.assets;
in
assert lib.assertMsg (lib.hasPrefix "sha256:" (
  asset.digest or ""
)) "PSScriptAnalyzer release asset must provide a SHA-256 digest";
stdenvNoCC.mkDerivation {
  pname = "psscriptanalyzer";
  inherit version;
  # The locked metadata selects and verifies the upstream release asset.
  # Formatting itself never downloads dependencies.
  src = fetchurl {
    url = asset.browser_download_url;
    sha256 = lib.removePrefix "sha256:" asset.digest;
  };

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
