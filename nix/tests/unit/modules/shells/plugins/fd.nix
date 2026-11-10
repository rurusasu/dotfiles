{ homeConfigurations }:
let
  inherit (homeConfigurations) homes;
in
{
  testFdFzfCommandsAcrossHomes = {
    expr = map (home: {
      commands = {
        default = home.config.programs.zsh.sessionVariables.FZF_DEFAULT_COMMAND;
        file = home.config.programs.fzf.fileWidget.zsh.command;
        directory = home.config.programs.fzf.changeDirWidget.zsh.command;
      };
    }) homes;
    expected = map (_: {
      commands = {
        default = "fd --type f --hidden --exclude .git --follow";
        file = "fd --type f --hidden --exclude .git --follow";
        directory = "fd --type d --hidden --exclude .git";
      };
    }) homes;
  };
}
