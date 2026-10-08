_: {
  programs.git.settings.alias.gtr =
    ''!f() { [ -z "$1" ] && echo 'Usage: git gtr <branch>' && return 1; root=$(git worktree list --porcelain | grep '^worktree ' | head -1 | sed 's/^worktree //'); git worktree add "$root/.worktrees/$1" "$1"; }; f'';
}
