# Search options are supplied by fzf.nix, shared with Bash and FZF_*_COMMAND.
typeset -ga __fzf_fd_opts=("$@")

# Alt+D (Option+D on macOS): fzf directory search and cd
__fzf_cd_widget() {
  local dir
  dir="$(fd "${__fzf_fd_opts[@]}" --absolute-path -t d . . | fzf)" && cd "$dir"
  zle reset-prompt
}
zle -N __fzf_cd_widget
bindkey '^[d' __fzf_cd_widget

# Alt+T (Option+T on macOS): fzf file/directory search and insert path
__fzf_file_widget() {
  local selected
  selected="$(fd "${__fzf_fd_opts[@]}" --absolute-path . . | fzf)"
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
