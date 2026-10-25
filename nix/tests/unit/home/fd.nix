{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations)
    homes
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
    expr = map (
      home:
      let
        inherit (home.config) programs;
        zshrc =
          home.config.home.file."${lib.removePrefix "${home.config.home.homeDirectory}/" programs.zsh.dotDir}/.zshrc".text;
      in
      lib.hasInfix "alias -- find=${lib.escapeShellArg programs.zsh.shellAliases.find}" zshrc
    ) homes;
    expected = map (_: true) homes;
  };

  testFdFzfIntegrationIsGeneratedAcrossHomes = {
    expr = map (
      home:
      let
        zshrc =
          home.config.home.file."${lib.removePrefix "${home.config.home.homeDirectory}/" home.config.programs.zsh.dotDir}/.zshrc".text;
      in
      {
        # The source block includes the guard, default and widget commands,
        # and both completion functions with the configured fd options.
        configuredIntegration =
          lib.trim configuredIntegration != "" && lib.hasInfix (lib.trim configuredIntegration) zshrc;
        guarded = lib.hasInfix "if command -v fzf >/dev/null 2>&1; then" zshrc;
        pathCompletion = lib.hasInfix "_fzf_compgen_path() {" zshrc;
        directoryCompletion = lib.hasInfix "_fzf_compgen_dir() {" zshrc;
        obsoleteRipgrepDefault = lib.hasInfix "export FZF_DEFAULT_COMMAND='rg --files'" zshrc;
      }
    ) homes;
    expected = map (_: {
      configuredIntegration = true;
      guarded = true;
      pathCompletion = true;
      directoryCompletion = true;
      obsoleteRipgrepDefault = false;
    }) homes;
  };
}
