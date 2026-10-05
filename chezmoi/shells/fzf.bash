# Windows Bash configuration; Unix uses nix/home/fzf.nix.

# fd/fzf defaults (mirrors Nix defaults)
FD_DEFAULT_OPTS="--hidden --follow --no-ignore-vcs --max-depth 10"
export FZF_DEFAULT_COMMAND="fd $FD_DEFAULT_OPTS --absolute-path --type f . ."
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND="fd $FD_DEFAULT_OPTS --absolute-path --type d . ."
export FZF_DEFAULT_OPTS="--height=40% --layout=reverse --border --prompt='> '"

# Alt+D: fzf directory search and cd
__fzf_cd_widget() {
  local dir
  dir="$(fd $FD_DEFAULT_OPTS --absolute-path -t d . . | fzf)" || return
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
  selected="$(fd $FD_DEFAULT_OPTS --absolute-path . . | fzf)"
  if [[ -n $selected ]]; then
    READLINE_LINE="${READLINE_LINE}${selected}"
    READLINE_POINT=${#READLINE_LINE}
  fi
}
bind -x '"\et": __fzf_file_widget'

# Alt+R: fzf command history search
__fzf_history_widget() {
  local selected
  selected="$(history | sed 's/^ *[0-9]\+ *//' | fzf --tac)"
  if [[ -n $selected ]]; then
    READLINE_LINE="$selected"
    READLINE_POINT=${#READLINE_LINE}
  fi
}
bind -x '"\er": __fzf_history_widget'
