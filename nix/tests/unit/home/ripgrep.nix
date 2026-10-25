{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations)
    homes
    sharedConfig
    lib
    ;
  configuredIntegration =
    (import ../../../home/shells/plugins/ripgrep.nix {
      lib = lib // {
        mkBefore = value: value;
      };
    }).programs.zsh.initContent;
in
{
  testRipgrepSettingsAcrossHomes = {
    expr = map (home: {
      enabled = home.config.programs.ripgrep.enable;
      packageName = home.config.programs.ripgrep.package.pname;
      arguments = home.config.programs.ripgrep.arguments;
      configPath = home.config.home.sessionVariables.RIPGREP_CONFIG_PATH;
      config = home.config.home.file."${home.config.xdg.configHome}/ripgrep/ripgreprc".text;
    }) homes;
    expected = map (_: {
      enabled = sharedConfig.programs.ripgrep.enable;
      packageName = sharedConfig.programs.ripgrep.package.pname;
      arguments = sharedConfig.programs.ripgrep.arguments;
      configPath = sharedConfig.home.sessionVariables.RIPGREP_CONFIG_PATH;
      config = sharedConfig.home.file."${sharedConfig.xdg.configHome}/ripgrep/ripgreprc".text;
    }) homes;
  };

  testRipgrepFzfIntegrationIsGeneratedAcrossHomes = {
    # The canonical block covers its guard, function, both reload bindings,
    # bat preview, and editor invocation without copying those shell commands.
    expr = map (home: {
      configuredIntegration =
        lib.trim configuredIntegration != ""
        && lib.hasInfix (lib.trim configuredIntegration) home.config.programs.zsh.initContent;
      guarded = lib.hasInfix "if command -v rg >/dev/null 2>&1 && command -v fzf >/dev/null 2>&1; then" home.config.programs.zsh.initContent;
      functionDefined = lib.hasInfix "rfg() {" home.config.programs.zsh.initContent;
    }) homes;
    expected = map (_: {
      configuredIntegration = true;
      guarded = true;
      functionDefined = true;
    }) homes;
  };
}
