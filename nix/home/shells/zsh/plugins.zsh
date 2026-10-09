# zsh-autocomplete itself is loaded earlier by Home Manager's plugins option.
# Register command completions after it has installed its compdef queue.
if command -v kubectl >/dev/null 2>&1; then
  source <(kubectl completion zsh)
fi
if command -v kind >/dev/null 2>&1; then
  source <(kind completion zsh)
fi
if command -v helm >/dev/null 2>&1; then
  source <(helm completion zsh)
fi
if command -v task >/dev/null 2>&1; then
  eval "$(task --completion zsh)"
fi
