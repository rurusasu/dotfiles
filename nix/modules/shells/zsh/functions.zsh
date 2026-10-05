# tm: ghq + fzf でリポジトリ選択 → tmux セッション作成/切替
tm() {
  if ! command -v tmux &>/dev/null; then
    cd "$(ghq list --full-path | fzf)" 2>/dev/null
    return
  fi
  local repo_slug session_name repo_dir
  repo_slug=$(ghq list | fzf) || return
  session_name=${repo_slug##*/}
  repo_dir="$(ghq root)/$repo_slug"
  tmux has-session -t "$session_name" 2>/dev/null ||
    tmux new-session -d -c "$repo_dir" -s "$session_name"
  if [[ -n "${TMUX:-}" ]]; then
    tmux switch-client -t "$session_name"
  else
    tmux attach-session -t "$session_name"
  fi
}

# Run task from the dotfiles root without changing cwd.
dotf() { (cd ~/.dotfiles && task "$@") }

codex() {
  local __dotfiles_had_force_secret_load=0
  local __dotfiles_previous_force_secret_load="${DOTFILES_FORCE_SECRET_LOAD:-}"
  if [ "${DOTFILES_FORCE_SECRET_LOAD+x}" = x ]; then
    __dotfiles_had_force_secret_load=1
  fi

  if { [ -z "${GITHUB_PAT_TOKEN:-}" ] || [ -z "${GITHUB_WORK_TOKEN:-}" ] || [ -z "${TAVILY_API_KEY:-}" ]; } && [ -f "$HOME/.config/shell/secret.sh" ]; then
    export DOTFILES_FORCE_SECRET_LOAD=1
    source "$HOME/.config/shell/secret.sh"
    if [ "$__dotfiles_had_force_secret_load" = 1 ]; then
      export DOTFILES_FORCE_SECRET_LOAD="$__dotfiles_previous_force_secret_load"
    else
      unset DOTFILES_FORCE_SECRET_LOAD
    fi
  fi

  command codex "$@"
}

# 1Password-managed secrets (GITHUB_PAT_TOKEN, TAVILY_API_KEY, etc.).
[[ -f "$HOME/.config/shell/secret.sh" ]] && source "$HOME/.config/shell/secret.sh"

# GitHub CLI token switching for personal/work repositories.
[[ -f "$HOME/.config/shell/gh-token-switch.sh" ]] && source "$HOME/.config/shell/gh-token-switch.sh"
