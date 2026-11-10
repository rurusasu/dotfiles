{ homeConfigurations }:
let
  inherit (homeConfigurations) homes;
in
{
  testCodexConfigurationIsOwnedByHomeManagerAcrossHomes = {
    expr = map (
      home:
      let
        cfg = home.config.programs.codex;
      in
      {
        enabled = cfg.enable;
        appProvided = cfg.package == null;
        mutable = cfg.mutableSettings;
        mcpIntegration = cfg.enableMcpIntegration;
        configHome = home.config.home.sessionVariables.CODEX_HOME;
      }
    ) homes;
    expected = map (home: {
      enabled = true;
      appProvided = true;
      mutable = true;
      mcpIntegration = true;
      configHome = home.config.xdg.configHome + "/codex";
    }) homes;
  };

  testStandaloneDarwinCodexSharesItsHomeWithGuiClients = {
    expr = homeConfigurations.darwin.config.launchd.agents.codex-environment.config.ProgramArguments;
    expected = [
      "/bin/launchctl"
      "setenv"
      "CODEX_HOME"
      (homeConfigurations.darwin.config.xdg.configHome + "/codex")
    ];
  };
}
