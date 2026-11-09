{
  config,
  lib,
  ...
}:
{
  config = lib.mkIf config.programs.bash.enable {
    home.sessionPath = [
      (config.home.homeDirectory + "/.bun/bin")
      (config.home.homeDirectory + "/.local/bin")
      (config.home.homeDirectory + "/bin")
      (config.home.homeDirectory + "/.local/npm/bin")
    ];
    # Bash configuration is generated together with terminal shell integrations.
    programs.bash = {
      sessionVariables = {
        USER_ID = "$(id -u)";
        GROUP_ID = "$(id -g)";
        NVM_DIR = config.home.homeDirectory + "/.nvm";
      };
      historyFile = config.home.homeDirectory + "/.bash_history";
      historySize = 1000;
      historyFileSize = 2000;
      historyControl = [ "ignoreboth" ];
      historyIgnore = [
        "ls"
        "cd"
        "exit"
      ];
      shellOptions = [
        "histappend"
        "extglob"
        "globstar"
        "checkjobs"
        "checkwinsize"
      ];
      shellAliases = {
        dotf = "task --dir ${lib.escapeShellArg (config.home.homeDirectory + "/.dotfiles")}";
      };

      initExtra = lib.mkBefore ''
        # Home Manager puts sessionVariables in .profile; also apply them to
        # interactive non-login shells before loading NVM.
        ${config.lib.shell.exportAll config.programs.bash.sessionVariables}

        # NVM's user-managed installation and its completion remain optional.
        [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
        [ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
      '';
    };
  };
}
