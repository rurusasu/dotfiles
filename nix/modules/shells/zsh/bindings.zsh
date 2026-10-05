# Backspace / Delete のキー設定。
bindkey '^?' backward-delete-char
bindkey '^H' backward-delete-char
if zmodload -F zsh/terminfo +p:terminfo; then
  if [[ -n "${terminfo[kdch1]:-}" ]]; then
    bindkey "${terminfo[kdch1]}" delete-char
  fi
fi
bindkey '^[[3~' delete-char
