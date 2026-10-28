{ homeConfigurations, files }:
let
  inherit (homeConfigurations)
    homes
    lib
    ;
in
{
  testFdFindAliasAcrossHomes = {
    expr = map (
      home:
      let
        inherit (home.config) programs;
      in
      lib.hasInfix "alias -- find=${lib.escapeShellArg programs.zsh.shellAliases.find}"
        home.config.home.file."${lib.removePrefix "${home.config.home.homeDirectory}/" programs.zsh.dotDir}/.zshrc".text
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
        commands = {
          default = home.config.programs.zsh.sessionVariables.FZF_DEFAULT_COMMAND;
          file = home.config.programs.fzf.fileWidget.zsh.command;
          directory = home.config.programs.fzf.changeDirWidget.zsh.command;
        };
        pathCompletion = lib.hasInfix "_fzf_compgen_path() {" zshrc;
        directoryCompletion = lib.hasInfix "_fzf_compgen_dir() {" zshrc;
        obsoleteRipgrepDefault = lib.hasInfix "export FZF_DEFAULT_COMMAND='rg --files'" zshrc;
      }
    ) homes;
    expected = map (_: {
      commands = {
        default = "fd --type f --hidden --exclude .git --follow";
        file = "fd --type f --hidden --exclude .git --follow";
        directory = "fd --type d --hidden --exclude .git";
      };
      pathCompletion = true;
      directoryCompletion = true;
      obsoleteRipgrepDefault = false;
    }) homes;
  };
}
