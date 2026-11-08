{ fixtures, homeConfigurations }:
let
  inherit (homeConfigurations)
    darwin
    wsl
    linux
    mkHome
    ;
  disabled = mkHome {
    system = "x86_64-linux";
    module = { lib, ... }: {
      imports = [ (fixtures.homeModule "wsl") ];
      programs.pi-coding-agent.enable = lib.mkForce false;
    };
  };
  piState = home: {
    enabled = home.config.programs.pi-coding-agent.enable;
    installed = builtins.any (
      package: package.drvPath == home.config.programs.pi-coding-agent.package.drvPath
    ) home.config.home.packages;
    hasManagedSettings = home.config.programs.pi-coding-agent.settings != { };
    hasManagedModels = home.config.programs.pi-coding-agent.models != { };
  };
in
{
  testPiEnabledOnlyOnDarwinAndWsl = {
    expr = map piState [
      darwin
      wsl
      linux
    ];
    expected = [
      {
        enabled = true;
        installed = true;
        hasManagedSettings = true;
        hasManagedModels = true;
      }
      {
        enabled = true;
        installed = true;
        hasManagedSettings = true;
        hasManagedModels = true;
      }
      {
        enabled = false;
        installed = false;
        hasManagedSettings = false;
        hasManagedModels = false;
      }
    ];
  };
  testPiModuleCanBeImportedWithoutEnablingPi = {
    expr = piState disabled;
    expected = {
      enabled = false;
      installed = false;
      hasManagedSettings = false;
      hasManagedModels = false;
    };
  };
  testPiDefaultsToTheConfiguredLocalStrataModel = {
    expr =
      map
        (
          home:
          let
            pi = home.config.programs.pi-coding-agent;
            provider = pi.models.providers.${pi.settings.defaultProvider};
            model = builtins.head provider.models;
          in
          {
            provider = pi.settings.defaultProvider;
            model = pi.settings.defaultModel == model.id;
            endpoint = provider.baseUrl;
            api = provider.api;
            thinking = pi.settings.defaultThinkingLevel;
            context = model.contextWindow;
            output = model.maxTokens;
            compactionFits =
              pi.settings.compaction.reserveTokens + pi.settings.compaction.keepRecentTokens
              < model.contextWindow;
          }
        )
        [
          darwin
          wsl
        ];
    expected = builtins.genList (_: {
      provider = "strata";
      model = true;
      endpoint = "http://127.0.0.1:8080/v1";
      api = "openai-completions";
      thinking = "off";
      context = 32768;
      output = 4096;
      compactionFits = true;
    }) 2;
  };
}
