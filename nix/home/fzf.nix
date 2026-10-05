{ config, ... }:
let
  fdOpts = "--hidden --follow --no-ignore-vcs --max-depth 10";
in
{
  programs.fzf = {
    # Keep the custom Alt+D/T/R widgets without adding standard Ctrl bindings.
    enableBashIntegration = false;
    enableZshIntegration = false;
    enableFishIntegration = false;
    enableNushellIntegration = false;
    defaultCommand = "fd ${fdOpts} --absolute-path --type f . .";
    fileWidget.command = config.programs.fzf.defaultCommand;
    changeDirWidget.command = "fd ${fdOpts} --absolute-path --type d . .";
    defaultOptions = [
      "--height=40%"
      "--layout=reverse"
      "--border"
      "--prompt='> '"
    ];
  };

  programs.bash.initExtra = ''
    # Alt+D: fzf directory search and cd
    __fzf_cd_widget() {
      local dir
      dir="$(fd ${fdOpts} --absolute-path -t d . . | fzf)" || return
      cd "$dir" || return

      # Show cwd change immediately even if prompt redraw is delayed.
      printf '\n%s\n' "$PWD"

      READLINE_LINE=""
      READLINE_POINT=0
    }
    bind -x '"\ed": __fzf_cd_widget'

    # Alt+T: fzf file/directory search and insert
    __fzf_file_widget() {
      local selected
      selected="$(fd ${fdOpts} --absolute-path . . | fzf)"
      if [[ -n "$selected" ]]; then
        READLINE_LINE="''${READLINE_LINE}''${selected}"
        READLINE_POINT=''${#READLINE_LINE}
      fi
    }
    bind -x '"\et": __fzf_file_widget'

    # Alt+R: fzf command history search
    __fzf_history_widget() {
      local selected
      selected="$(history | sed 's/^ *[0-9]\+ *//' | fzf --tac)"
      if [[ -n "$selected" ]]; then
        READLINE_LINE="$selected"
        READLINE_POINT=''${#READLINE_LINE}
      fi
    }
    bind -x '"\er": __fzf_history_widget'
  '';

  programs.zsh.initContent = ''
    # Alt+D (Option+D on macOS): fzf directory search and cd
    __fzf_cd_widget() {
      local dir
      dir="$(fd ${fdOpts} --absolute-path -t d . . | fzf)" && cd "$dir"
      zle reset-prompt
    }
    zle -N __fzf_cd_widget
    bindkey '^[d' __fzf_cd_widget

    # Alt+T (Option+T on macOS): fzf file search and insert path
    __fzf_file_widget() {
      local selected
      selected="$(fd ${fdOpts} --absolute-path . . | fzf)"
      if [[ -n "$selected" ]]; then
        LBUFFER="$LBUFFER$selected"
      fi
      zle reset-prompt
    }
    zle -N __fzf_file_widget
    bindkey '^[t' __fzf_file_widget

    # Alt+R (Option+R on macOS): fzf command history search
    __fzf_history_widget() {
      local selected
      selected="$(fc -ln 1 | fzf --tac)"
      if [[ -n "$selected" ]]; then
        BUFFER="$selected"
        CURSOR=$#BUFFER
      fi
      zle reset-prompt
    }
    zle -N __fzf_history_widget
    bindkey '^[r' __fzf_history_widget
  '';
}
