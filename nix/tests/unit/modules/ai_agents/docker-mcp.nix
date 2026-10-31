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
        "aarch64-linux"
        "aarch64-darwin"
      ];
in
{
  testDockerMcpIsInstalledAndLinkedByHomeManager = {
    expr = map (home: {
      installed = builtins.any (package: (package.pname or "") == "docker-mcp") home.config.home.packages;
      linked = builtins.baseNameOf home.config.home.file.".docker/cli-plugins/docker-mcp".source;
    }) homes;
    expected = map (_: {
      installed = true;
      linked = "docker-mcp";
    }) homes;
  };

  testDockerMcpForcesItsCliPluginLink = {
    expr = map (home: home.config.home.file.".docker/cli-plugins/docker-mcp".force) homes;
    expected = map (_: true) homes;
  };

  testDockerMcpServersAreDeclarativeWithoutMutableProfiles = {
    expr = map (home: home.config.programs.mcp.servers.MCP_DOCKER.args) homes;
    expected = map (_: [
      "mcp"
      "gateway"
      "run"
      "--servers"
      "context7,deepwiki,exa,firecrawl,github-official,obsidian,playwright,tavily"
    ]) homes;
  };

  testDockerMcpUsesTheEffectiveDockerConfigurationDirectory = {
    expr =
      map
        (
          settings:
          let
            home = fixtures.mkHome "x86_64-linux" [
              ({ lib, ... }: {
                programs.mcp.enable = true;
                xdg.enable = true;
                home.stateVersion = lib.mkForce "26.05";
              })
              settings.module
            ];
          in
          home.config.home.file.".docker/cli-plugins/docker-mcp".target
          == "${settings.directory}/cli-plugins/docker-mcp"
        )
        [
          {
            module = { };
            directory = ".docker";
          }
          {
            module = { lib, ... }: {
              home.sessionVariables.DOCKER_CONFIG = lib.mkForce "/home/test-user/.custom/docker";
            };
            directory = ".custom/docker";
          }
        ];
    expected = [
      true
      true
    ];
  };

  testDockerMcpExplicitDockerConfigIsSharedWithClients = {
    expr = map (
      home:
      home.config.home.sessionVariables.DOCKER_CONFIG
      == home.config.programs.mcp.servers.MCP_DOCKER.env.DOCKER_CONFIG
    ) homes;
    expected = [
      true
      true
      true
    ];
  };

  testDockerMcpRejectsMissingOrEmptyDockerConfig = {
    expr =
      map
        (
          override:
          let
            home = fixtures.mkHome "x86_64-linux" [
              { programs.mcp.enable = true; }
              override
            ];
          in
          (builtins.tryEval home.config.home.file.".docker/cli-plugins/docker-mcp".target).success
        )
        [
          ({ lib, ... }: { home.sessionVariables = lib.mkForce { }; })
          ({ lib, ... }: { home.sessionVariables.DOCKER_CONFIG = lib.mkForce ""; })
        ];
    expected = [
      false
      false
    ];
  };
}
