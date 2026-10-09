{ config, ... }:
{
  programs.zsh = {
    dotDir = "${config.xdg.configHome}/zsh";
    setOptions = [
      "AUTO_CD"
      "NO_BEEP"
      "NUMERIC_GLOB_SORT"
    ];
    history = {
      path = "${config.xdg.stateHome}/zsh/history";
      size = 10000;
      save = 10000;
      append = true;
      share = true;
      extended = true;
      ignoreDups = true;
      ignoreSpace = true;
      saveNoDups = true;
      expireDuplicatesFirst = true;
    };

    initContent = ''
      source ${./bindings.zsh}
      source ${./aliases.zsh}
      source ${./plugins.zsh}
      source ${./prompt.zsh}
    '';
  };
}
