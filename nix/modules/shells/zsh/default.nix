{
  config,
  lib,
  pkgs,
  ...
}:
{
  # ── Shell: zsh ────────────────────────────────────────────────────────
  programs.zsh = {
    package = pkgs.zsh;
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
  };

  # zsh-autocomplete writes recent cd locations under XDG_DATA_HOME/zsh.
  # The plugin does not create that parent directory itself.
  home.activation.createZshDataDirectory = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p -- ${lib.escapeShellArg "${config.xdg.dataHome}/zsh"}
  '';
}
