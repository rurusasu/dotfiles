{ homeConfigurations }:
let
  inherit (homeConfigurations) homes;
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
      }
    ) homes;
    expected = map (home: {
      history = {
        historyFile = "${home.config.home.homeDirectory}/.bash_history";
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
    }) homes;
  };
}
