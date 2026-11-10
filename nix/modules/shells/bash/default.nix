{
  config,
  lib,
  ...
}:
{
  config = lib.mkMerge [
    { programs.bash.enable = true; }
    (lib.mkIf config.programs.bash.enable {
      # Bash configuration is generated together with terminal shell integrations.
      programs.bash = {
        sessionVariables = {
          USER_ID = "$(id -u)";
          GROUP_ID = "$(id -g)";
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

        initExtra = lib.mkBefore ''
          # Home Manager puts sessionVariables in .profile; also apply them to
          # interactive non-login shells.
          ${config.lib.shell.exportAll config.programs.bash.sessionVariables}
        '';
      };
    })
  ];
}
