{
  inputs,
  pkgs,
  code,
}:
{
  docker-mcp =
    let
      package = (code.nix.modules.ai_agents.mcp-packages { inherit inputs pkgs; }).docker-mcp;
    in
    pkgs.runCommand "docker-mcp-plugin-check"
      {
        nativeBuildInputs = [
          pkgs.docker-client
          pkgs.jq
        ];
      }
      ''
        export HOME="$TMPDIR/home"
        export DOCKER_CONFIG="$HOME/.docker"
        mkdir -p "$DOCKER_CONFIG/cli-plugins"
        ln -s ${pkgs.lib.getExe package} "$DOCKER_CONFIG/cli-plugins/docker-mcp"
        if env -u DOCKER_CONFIG ${pkgs.lib.getExe package} version >missing-config.log 2>&1; then
          echo 'Docker MCP must reject an unset DOCKER_CONFIG' >&2
          exit 1
        fi
        grep -q 'DOCKER_CONFIG' missing-config.log
        if DOCKER_CONFIG= ${pkgs.lib.getExe package} version >empty-config.log 2>&1; then
          echo 'Docker MCP must reject an empty DOCKER_CONFIG' >&2
          exit 1
        fi
        test "$(docker mcp version)" = "v${package.version}"
        ${pkgs.lib.getExe package} docker-cli-plugin-metadata | jq -e '.SchemaVersion == "0.1.0"'
        docker mcp gateway run --help | grep -q -- '--servers'
        touch "$out"
      '';
}
