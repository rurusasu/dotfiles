{ homeConfigurations }:
let
  inherit (homeConfigurations) homes lib;
in
{
  testBashEnabled = {
    expr = map (home: home.config.programs.bash.enable) homes;
    expected = map (_: true) homes;
  };

  testBashConfiguration = {
    expr = map (
      home:
      let
        bash = home.config.programs.bash;
        rc = home.config.home.file.".bashrc".source.text;
      in
      {
        history = {
          inherit (bash)
            historyFile
            historySize
            historyFileSize
            historyControl
            historyIgnore
            shellOptions
            ;
        };
        starshipIntegration = home.config.programs.starship.enableBashIntegration;
        initialization = lib.hasInfix (builtins.unsafeDiscardStringContext bash.initExtra) rc;
        loginConfiguration =
          lib.hasInfix (builtins.unsafeDiscardStringContext bash.profileExtra)
            home.config.home.file.".profile".source.text;
        aliases = lib.mapAttrsToList (
          name: value:
          lib.hasInfix (builtins.unsafeDiscardStringContext "alias -- ${name}=${lib.escapeShellArg value}") rc
        ) bash.shellAliases;
      }
    ) homes;
    expected = map (home: {
      history = {
        historyFile = "$HOME/.bash_history";
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
      };
      starshipIntegration = true;
      initialization = true;
      loginConfiguration = true;
      aliases = lib.mapAttrsToList (_: _: true) home.config.programs.bash.shellAliases;
    }) homes;
  };
}
