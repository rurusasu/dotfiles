# Zsh search defaults. Bash keeps the shared defaults from fzf.nix.
if command -v fd >/dev/null 2>&1; then
  typeset -g __fzf_fd_command=fd
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --strip-cwd-prefix'
elif command -v fdfind >/dev/null 2>&1; then
  # fd is named fdfind on Ubuntu.
  typeset -g __fzf_fd_command=fdfind
  export FZF_DEFAULT_COMMAND='fdfind --type f --hidden --strip-cwd-prefix'
else
  unset __fzf_fd_command FZF_DEFAULT_COMMAND
fi

# Ctrl-T uses the same file search through fzf's standard Zsh integration.
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"

# Compact UI
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'
