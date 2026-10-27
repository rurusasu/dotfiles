{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  docker-client,
  releaseMetadata,
}:
let
  release = builtins.head (builtins.fromJSON (builtins.readFile releaseMetadata));
  platform =
    {
      x86_64-linux = "linux-amd64";
      aarch64-linux = "linux-arm64";
      aarch64-darwin = "darwin-arm64";
    }
    .${stdenvNoCC.hostPlatform.system};
  asset =
    lib.findSingle (asset: asset.name == "docker-mcp-${platform}.tar.gz")
      (throw "Docker MCP release has no asset for ${platform}")
      (throw "Docker MCP release has multiple assets for ${platform}")
      release.assets;
in
assert lib.assertMsg (lib.hasPrefix "sha256:" (
  asset.digest or ""
)) "Docker MCP release asset must provide a SHA-256 digest";
stdenvNoCC.mkDerivation {
  pname = "docker-mcp";
  version = lib.removePrefix "v" release.tag_name;
  src = fetchurl {
    url = asset.browser_download_url;
    sha256 = lib.removePrefix "sha256:" asset.digest;
  };
  nativeBuildInputs = [ makeWrapper ];
  sourceRoot = ".";
  dontBuild = true;
  dontStrip = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 docker-mcp "$out/libexec/docker-mcp"
    makeWrapper "$out/libexec/docker-mcp" "$out/bin/docker-mcp" \
      --run ${lib.escapeShellArg '': "''${DOCKER_CONFIG:?Docker MCP requires DOCKER_CONFIG}"''} \
      --prefix PATH : ${lib.makeBinPath [ docker-client ]} \
      ${lib.optionalString stdenvNoCC.hostPlatform.isLinux "--set-default DOCKER_MCP_IN_CONTAINER 1"}
    runHook postInstall
  '';
  meta = {
    description = "Docker MCP CLI plugin and gateway";
    homepage = "https://github.com/docker/mcp-gateway";
    license = lib.licenses.mit;
    mainProgram = "docker-mcp";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
