{
  config,
  pkgs,
  ...
}:
{
  # ── Shell: zsh ────────────────────────────────────────────────────────
  programs.zsh = {
    enable = true;
    package = pkgs.zsh;
    setOptions = [
      "AUTO_CD"
      "NO_BEEP"
      "NUMERIC_GLOB_SORT"
    ];
    # 補完パッケージは維持し、compinit は zsh-autocomplete に任せる。
    enableCompletion = true;
    completionInit = "";
    plugins = [
      {
        name = "zsh-autocomplete";
        src = pkgs.zsh-autocomplete;
        file = "share/zsh-autocomplete/zsh-autocomplete.plugin.zsh";
      }
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
      source ${../../../../scripts/sh/dcnvim.sh}
      source ${./functions.zsh}
    '';
  };
}
