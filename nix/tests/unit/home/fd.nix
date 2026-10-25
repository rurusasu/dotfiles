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
    (import ../../../home/shells/plugins/fd.nix {
      lib = lib // {
        mkBefore = value: value;
      };
    }).programs.zsh.initContent;
in
{
  testFdFindAliasAcrossHomes = {
    expr = map (home: home.config.programs.zsh.shellAliases.find) homes;
    expected = map (_: sharedConfig.programs.zsh.shellAliases.find) homes;
  };

  testFdFzfIntegrationIsGeneratedAcrossHomes = {
    expr = map (home: {
      # The source block includes the guard, default and widget commands,
      # and both completion functions with the configured fd options.
      configuredIntegration =
        lib.trim configuredIntegration != ""
        && lib.hasInfix (lib.trim configuredIntegration) home.config.programs.zsh.initContent;
      guarded = lib.hasInfix "if command -v fzf >/dev/null 2>&1; then" home.config.programs.zsh.initContent;
      pathCompletion = lib.hasInfix "_fzf_compgen_path() {" home.config.programs.zsh.initContent;
      directoryCompletion = lib.hasInfix "_fzf_compgen_dir() {" home.config.programs.zsh.initContent;
      obsoleteRipgrepDefault = lib.hasInfix "export FZF_DEFAULT_COMMAND='rg --files'" home.config.programs.zsh.initContent;
    }) homes;
    expected = map (_: {
      configuredIntegration = true;
      guarded = true;
      pathCompletion = true;
      directoryCompletion = true;
      obsoleteRipgrepDefault = false;
    }) homes;
  };
}
