# Emit OSC 7 so terminals can open split/tab in the current directory.
# Starship initialization remains managed by Home Manager.
autoload -Uz add-zsh-hook
__emit_osc7_cwd() {
  printf '\033]7;file://%s%s\033\\' "$HOST" "$PWD"
}
add-zsh-hook precmd __emit_osc7_cwd

# Disable mouse reporting at the shell prompt. Mouse-aware programs re-enable it.
__disable_mouse_reporting() {
  printf '\033[?1000l\033[?1002l\033[?1003l\033[?1006l' 2>/dev/null
}
add-zsh-hook precmd __disable_mouse_reporting
