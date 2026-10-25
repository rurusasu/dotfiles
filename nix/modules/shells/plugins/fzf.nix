{ config, lib, ... }:
{
  programs.fzf = {
    enable = true;
    # Zsh uses standard Ctrl+T/R and Alt+C bindings.
    enableBashIntegration = false;
    enableZshIntegration = true;
    enableFishIntegration = false;
    enableNushellIntegration = false;
    defaultOptions = [
      "--height=60%"
      "--layout=reverse"
      "--border"
      "--prompt=> "
    ];
    fileWidget.zsh.options = [
      "--preview ${
        lib.escapeShellArg (
          if config.programs.bat.enable then
            "bat --color=always --style=numbers --line-range=:200 -- {}"
          else
            "cat -- {}"
        )
      }"
      "--preview-window=right:40%"
    ];
    changeDirWidget.zsh.options = [
      "--preview ${
        lib.escapeShellArg (
          if config.programs.eza.enable then
            "eza --tree --level=2 --icons=always --color=always -- {}"
          else
            "ls -la -- {}"
        )
      }"
      "--preview-window=right:60%"
    ];
  };
}
