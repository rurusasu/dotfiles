{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  fixtures = homeConfigurations;
  inherit (fixtures)
    homes
    lib
    linux
    sharedConfig
    ;
  sharedZsh = sharedConfig.programs.zsh;
  sharedSources = [
    "source ${../../../home/shells/zsh/bindings.zsh}"
    "source ${../../../home/shells/zsh/aliases.zsh}"
    "source ${../../../home/shells/zsh/prompt.zsh}"
  ];
in
{
  testLinuxHomeModuleRetainsSharedShellConfiguration = {
    expr = builtins.elem "source ${../../../home/shells/zsh/aliases.zsh}" (
      lib.splitString "\n" linux.config.programs.zsh.initContent
    );
    expected = true;
  };

  testZshUserSettingsRetainHistoryAndSourceOrderAcrossHomes = {
    expr = map (home: {
      enabled = home.config.programs.zsh.enable;
      dotDir = home.config.programs.zsh.dotDir;
      historyPath = home.config.programs.zsh.history.path;
      historySize = home.config.programs.zsh.history.size;
      historySave = home.config.programs.zsh.history.save;
      historyShared = home.config.programs.zsh.history.share;
      options = home.config.programs.zsh.setOptions;
      sources = builtins.filter (line: builtins.elem line sharedSources) (
        lib.splitString "\n" home.config.programs.zsh.initContent
      );
    }) homes;
    expected = map (_: {
      enabled = sharedZsh.enable;
      inherit (sharedZsh) dotDir;
      historyPath = sharedZsh.history.path;
      historySize = sharedZsh.history.size;
      historySave = sharedZsh.history.save;
      historyShared = sharedZsh.history.share;
      options = sharedZsh.setOptions;
      sources = sharedSources;
    }) homes;
  };

  testZshCompletionIntegrationAcrossHomes = {
    expr = map (home: {
      completionsEnabled = home.config.programs.zsh.enableCompletion;
      packageCompletions = lib.hasInfix "$profile/share/zsh/site-functions" home.config.programs.zsh.initContent;
      completionPlugin =
        sharedZsh.plugins != [ ]
        && builtins.all (
          plugin:
          builtins.elem plugin.name (map (configured: configured.name) home.config.programs.zsh.plugins)
        ) sharedZsh.plugins;
    }) homes;
    expected = map (_: {
      completionsEnabled = sharedZsh.enableCompletion;
      packageCompletions = true;
      completionPlugin = true;
    }) homes;
  };
}
