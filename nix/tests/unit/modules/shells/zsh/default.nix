{ homeConfigurations }:
let
  inherit (homeConfigurations) homes;
in
{
  testZshConfigurationAcrossHomes = {
    expr = map (home: {
      inherit (home.config.programs.zsh)
        enable
        dotDir
        enableCompletion
        completionInit
        ;
      history = {
        inherit (home.config.programs.zsh.history) size save path;
      };
      editingOptions = builtins.all (option: builtins.elem option home.config.programs.zsh.setOptions) [
        "AUTO_CD"
        "NO_BEEP"
        "NUMERIC_GLOB_SORT"
      ];
      completionPlugins = map (plugin: toString plugin.src) home.config.programs.zsh.plugins;
    }) homes;
    expected = map (home: {
      enable = true;
      dotDir = home.config.xdg.configHome + "/zsh";
      editingOptions = true;
      enableCompletion = true;
      completionInit = "";
      history = {
        size = 10000;
        save = 10000;
        path = home.config.xdg.stateHome + "/zsh/history";
      };
      completionPlugins = [ (toString home.pkgs.zsh-autocomplete) ];
    }) homes;
  };
}
