{
  lib,
  buildGo126Module,
  makeWrapper,
  dockerCompat,
  apiEnvironment,
  source,
}:
# Match upstream's Go 1.26 toolchain; its vendored gRPC is not Go 1.27 compatible.
# https://github.com/docker/mcp-gateway/blob/7e0f34277c91855ad861eeff536b4fdc77420593/Dockerfile#L3
buildGo126Module (finalAttrs: {
  pname = "docker-mcp";
  version = "unstable-${source.shortRev}";
  src = source;
  vendorHash = null;
  subPackages = [ "cmd/docker-mcp" ];
  env.CGO_ENABLED = 0;
  ldflags = [
    "-s"
    "-w"
    "-X github.com/docker/mcp-gateway/cmd/docker-mcp/version.Version=v${finalAttrs.version}"
  ];
  nativeBuildInputs = [ makeWrapper ];
  postInstall = ''
    mkdir -p "$out/libexec"
    mv "$out/bin/docker-mcp" "$out/libexec/docker-mcp"
    makeWrapper "$out/libexec/docker-mcp" "$out/bin/docker-mcp" \
      --run ${lib.escapeShellArg '': "''${DOCKER_CONFIG:?Docker MCP requires DOCKER_CONFIG}"''} \
      --prefix PATH : ${lib.makeBinPath [ dockerCompat ]} \
      --run ${lib.escapeShellArg apiEnvironment} \
      --set-default DOCKER_MCP_IN_CONTAINER 1
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
  };
})
