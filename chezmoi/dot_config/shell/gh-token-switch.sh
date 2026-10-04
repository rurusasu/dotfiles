# GitHub CLI token switching for personal/work repositories.
# Sourced by ~/.bashrc after 1Password-managed secrets are loaded.

_dotfiles_git_remote_is_work() {
  command -v git >/dev/null 2>&1 || return 1
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1

  git config --get-regexp '^remote\..*\.url$' 2>/dev/null |
    awk '{print $2}' |
    grep -Eq '(^|[[:space:]])git@github-work:'
}

_dotfiles_path_is_work() {
  case "${PWD:-}" in
  /mnt/d/my_programing | /mnt/d/my_programing/* | D:/my_programing | D:/my_programing/* | D:\\my_programing | D:\\my_programing\\*)
    return 0
    ;;
  esac

  return 1
}

_dotfiles_github_repo_is_work() {
  _dotfiles_git_remote_is_work || _dotfiles_path_is_work
}

gh() {
  if _dotfiles_github_repo_is_work; then
    if [ -n "${GITHUB_WORK_TOKEN:-}" ]; then
      if [ -n "${DOTFILES_GH_BIN:-}" ]; then
        GH_TOKEN="$GITHUB_WORK_TOKEN" "$DOTFILES_GH_BIN" "$@"
      else
        GH_TOKEN="$GITHUB_WORK_TOKEN" command gh "$@"
      fi
      return $?
    fi

    printf 'gh: work repo detected, but GITHUB_WORK_TOKEN is not set; using existing GH_TOKEN\n' >&2
  fi

  if [ -n "${DOTFILES_GH_BIN:-}" ]; then
    "$DOTFILES_GH_BIN" "$@"
  else
    command gh "$@"
  fi
}
