# Alt+Q (Option+Q on macOS): zoxide interactive directory jump
__zoxide_zi_widget() {
  local result
  result="$(zoxide query -i)" && cd "$result"
  zle reset-prompt
}
zle -N __zoxide_zi_widget
bindkey '^[q' __zoxide_zi_widget
