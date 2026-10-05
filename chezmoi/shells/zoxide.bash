# Windows Bash integration; Unix uses nix/home/zoxide.nix.
export _ZO_EXCLUDE_DIRS="/mnt/wsl/*:/mnt/wslg/*"

if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init bash)"
fi

# Alt+Q: zoxide interactive (history-based directory jump)
__zoxide_zi_widget() {
  local result
  result="$(zoxide query -i)" || return
  cd "$result" || return

  # Show cwd change immediately even if prompt redraw is delayed.
  printf '\n%s\n' "$PWD"

  READLINE_LINE=""
  READLINE_POINT=0
}
bind -x '"\eq": __zoxide_zi_widget'
