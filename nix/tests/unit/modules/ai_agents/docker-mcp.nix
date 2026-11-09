{ fixtures }:
let
  homes =
    map
      (
        system:
        fixtures.mkHome system [
          ({ lib, ... }: {
            programs.mcp.enable = true;
            xdg.enable = true;
            home.stateVersion = lib.mkForce "26.05";
          })
        ]
      )
      [
        "x86_64-linux"
        "aarch64-darwin"
      ];
in
{
  testMcpUsesHermesStateWithoutInstallingItsCli = {
    expr =
      let
        home = fixtures.mkHome "x86_64-linux" [
          {
            programs.mcp.enable = true;
            services.hermes-agent = {
              enable = true;
              hermesHome = "/srv/hermes";
            };
          }
        ];
      in
      {
        cli = home.config.programs.hermes-agent.enable;
        sharesState = builtins.elem "HERMES_DATA_DIR=/srv/hermes" home.config.systemd.user.services.mcp-xapi.Service.Environment;
      };
    expected = {
      cli = false;
      sharesState = true;
    };
  };

  testMcpGatewayUsesItsManagedBinaryAndSecrets = {
    expr = map (
      home:
      let
        server = home.config.programs.mcp.servers.MCP_DOCKER;
        directory = home.config.home.sessionVariables.DOCKER_CONFIG;
      in
      {
        installed = builtins.any (package: (package.pname or "") == "docker-mcp") home.config.home.packages;
        command = builtins.baseNameOf server.command;
        sharedConfig = server.env.DOCKER_CONFIG == directory;
        secrets = builtins.elem "${directory}/mcp/secrets.env" server.args;
      }
    ) homes;
    expected = map (_: {
      installed = true;
      command = "docker-mcp";
      sharedConfig = true;
      secrets = true;
    }) homes;
  };
}
