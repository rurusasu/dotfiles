{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations) homes sharedConfig;
  codex = sharedConfig.programs.codex;
in
{
  testCodexConfigurationIsOwnedByHomeManagerAcrossHomes = {
    expr = map (home: {
      enabled = home.config.programs.codex.enable;
      appProvided =
        home.config.programs.codex.package == null || home.config.programs.codex.package ? chatgpt;
      mutable = home.config.programs.codex.mutableSettings;
      cleanup = home.config.programs.codex.settings.desktop;
      agents = home.config.programs.codex.settings.agents.fast_worker.config_file;
      hookCount = builtins.length (builtins.head home.config.programs.codex.hooks.PreToolUse).hooks;
      rules = builtins.attrNames home.config.programs.codex.rules;
      contextTakeover = home.config.home.file.".codex/AGENTS.override.md".force;
      mergeActivation = home.config.home.activation ? codexMutableSettings;
      noImmutableConfig = !(home.config.home.file ? ".codex/config.toml");
    }) homes;
    expected = map (_: {
      enabled = codex.enable;
      appProvided = true;
      mutable = codex.mutableSettings;
      cleanup = codex.settings.desktop;
      agents = codex.settings.agents.fast_worker.config_file;
      hookCount = builtins.length (builtins.head codex.hooks.PreToolUse).hooks;
      rules = builtins.attrNames codex.rules;
      contextTakeover = sharedConfig.home.file.".codex/AGENTS.override.md".force;
      mergeActivation = true;
      noImmutableConfig = true;
    }) homes;
  };
}
