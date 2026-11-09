{ pkgs, fixtures }:
let
  home = fixtures.mkHome pkgs.stdenv.hostPlatform.system [
    {
      services.hermes-agent = {
        enable = true;
        package = pkgs.hello;
      };
      programs.mcp.servers.runtime-secret = {
        command = "${pkgs.coreutils}/bin/printenv";
        args = [ "TEST_TOKEN" ];
        env.TEST_TOKEN.file = "/dev/stdin";
      };
    }
  ];
  server = home.config.services.hermes-agent.settings.mcp_servers.runtime-secret;
in
{
  hermes-mcp-environment =
    pkgs.runCommand "hermes-mcp-environment-check" { nativeBuildInputs = [ pkgs.coreutils ]; }
      ''
        token="$(printf '%s' 'runtime-fixture-token' | ${server.command} ${pkgs.lib.escapeShellArgs server.args})"
        test "$token" = 'runtime-fixture-token'
        touch "$out"
      '';
}
