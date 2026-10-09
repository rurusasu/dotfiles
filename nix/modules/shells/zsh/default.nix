{ pkgs, ... }:
{
  # ── Shell: zsh ────────────────────────────────────────────────────────
  programs.zsh = {
    enable = true;
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
}
