{ lib, ... }:
let
  previewInit = ''
    FZF_FILE_PREVIEW='cat -- {}'
    FZF_DIR_PREVIEW='ls -la -- {}'

    if command -v bat >/dev/null 2>&1; then
      FZF_FILE_PREVIEW='bat --color=always --style=numbers --line-range=:200 -- {}'
    fi
    if command -v eza >/dev/null 2>&1; then
      FZF_DIR_PREVIEW='eza --tree --level=2 --icons=always --color=always -- {}'
    fi

    export FZF_CTRL_T_OPTS="--preview '$FZF_FILE_PREVIEW' --preview-window=right:40%"
    export FZF_ALT_C_OPTS="--preview '$FZF_DIR_PREVIEW' --preview-window=right:60%"

    unset FZF_FILE_PREVIEW FZF_DIR_PREVIEW
  '';
in
{
  # Configure fzf through its documented environment variables.
  home.sessionVariables = {
    FZF_DEFAULT_OPTS = "--height=60% --layout=reverse --border --prompt=> ";
  };

  programs = {
    fzf = {
      # Zsh uses standard Ctrl+T/R and Alt+C bindings.
      enableBashIntegration = false;
      enableZshIntegration = true;
      enableFishIntegration = false;
      enableNushellIntegration = false;
    };

    zsh.initContent = lib.mkBefore previewInit;
  };
}
