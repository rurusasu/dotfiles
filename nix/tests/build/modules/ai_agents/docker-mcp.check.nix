{
  inputs,
  pkgs,
  code,
}:
{
  docker-mcp =
    let
      package = (code.nix.modules.ai_agents.mcp-packages { inherit inputs pkgs; }).docker-mcp;
      runtime = code.nix.modules.podman.runtime { inherit pkgs; };
    in
    pkgs.runCommand "docker-mcp-check" { } ''
      export HOME="$TMPDIR/home"
      export DOCKER_CONFIG="$HOME/.docker"
      export DOCKER_HOST="unix://$TMPDIR/podman.sock"
      mkdir -p "$DOCKER_CONFIG"
      test "$(${pkgs.lib.getExe package} version)" = "v${package.version}"
      ${pkgs.lib.getExe runtime.dockerCompat} --version | grep -F 'version ${pkgs.podman.version}'
      ${pkgs.lib.getExe package} gateway run --help >gateway-help.log
      grep -q -- '--servers' gateway-help.log
      touch "$out"
    '';
}
