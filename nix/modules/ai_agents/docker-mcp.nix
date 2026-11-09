{
  lib,
  buildGoModule,
  makeWrapper,
  dockerCompat,
  apiEnvironment,
  source,
}:
buildGoModule (finalAttrs: {
  pname = "docker-mcp";
  version = "unstable-${source.shortRev}";
  src = source;
  vendorHash = null;
  subPackages = [ "cmd/docker-mcp" ];
  # Match grpc-go upstream: x/net/http2 no longer exports TrailerPrefix on Go 1.27.
  postPatch = ''
    substituteInPlace vendor/google.golang.org/grpc/internal/transport/handler_server.go \
      --replace-fail 'http2.TrailerPrefix' 'http.TrailerPrefix'
  '';
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
