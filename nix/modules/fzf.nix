{ pkgs, ... }:
let
  fdOpts = "--hidden --follow --no-ignore-vcs --max-depth 10";
  fileCommand = "fd ${fdOpts} --absolute-path --type f . .";
  directoryCommand = "fd ${fdOpts} --absolute-path --type d . .";
in
{
  programs.fzf = {
    enable = true;
    package = pkgs.fzf;

    # Bash/Zsh use the repository's custom Alt+D/T/R widgets.
    enableBashIntegration = false;
    enableZshIntegration = false;

    defaultCommand = fileCommand;
    defaultOptions = [
      "--height=40%"
      "--layout=reverse"
      "--border"
      "--prompt='> '"
    ];
    fileWidget.command = fileCommand;
    changeDirWidget.command = directoryCommand;
  };
}
