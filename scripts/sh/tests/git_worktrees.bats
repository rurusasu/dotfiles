#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
  mkdir -p "$HOME"
  REPO="$BATS_TEST_TMPDIR/main repository"
  WORKTREE="$BATS_TEST_TMPDIR/feature worktree"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.name "Worktree test"
  git -C "$REPO" config user.email "worktree@example.invalid"
  git -C "$REPO" config commit.gpgsign false
  git -C "$REPO" commit -q --allow-empty -m initial
}

@test "repair converts Windows links without losing branch commits or dirty files" {
  chezmoi --config /dev/null --config-format toml --source "$REPO_ROOT/chezmoi" \
    --destination "$HOME" --cache "$BATS_TEST_TMPDIR/cache" \
    --persistent-state "$BATS_TEST_TMPDIR/state.boltdb" \
    --override-data '{"chezmoi":{"os":"windows"}}' \
    cat "$HOME/.config/git/config" >"$GIT_CONFIG_GLOBAL"
  git -C "$REPO" worktree add -q -b feature "$WORKTREE"
  printf 'committed\n' >"$WORKTREE/tracked.txt"
  git -C "$WORKTREE" add tracked.txt
  git -C "$WORKTREE" commit -qm feature
  printf 'unsaved\n' >>"$WORKTREE/tracked.txt"
  printf 'untracked\n' >"$WORKTREE/untracked.txt"
  before_head=$(git -C "$WORKTREE" rev-parse HEAD)
  before_status=$(git -C "$WORKTREE" status --porcelain)
  admin=$(git -C "$WORKTREE" rev-parse --absolute-git-dir)
  [[ $(cat "$WORKTREE/.git") == 'gitdir: ../'* ]]
  [[ $(cat "$admin/gitdir") == '../'* ]]
  printf '%s\n' 'D:/old/location/feature/.git' >"$admin/gitdir"
  printf 'gitdir: D:/old/location/main/.git/worktrees/%s\n' "$(basename "$admin")" >"$WORKTREE/.git"

  run task --dir "$REPO_ROOT" worktree:repair "REPO=$REPO" "WORKTREE=$WORKTREE"

  [ "$status" -eq 0 ]
  [ "$(git -C "$WORKTREE" rev-parse HEAD)" = "$before_head" ]
  [ "$(git -C "$WORKTREE" branch --show-current)" = feature ]
  [ "$(git -C "$WORKTREE" status --porcelain)" = "$before_status" ]
  [ "$(cat "$WORKTREE/tracked.txt")" = $'committed\nunsaved' ]
  [ "$(cat "$WORKTREE/untracked.txt")" = untracked ]
  [[ $(cat "$WORKTREE/.git") == 'gitdir: ../'* ]]
  [[ $(cat "$admin/gitdir") == '../'* ]]
  run task --dir "$REPO_ROOT" worktree:repair "REPO=$REPO" "WORKTREE=$BATS_TEST_TMPDIR/missing"
  [ "$status" -ne 0 ]
  [ "$(git -C "$WORKTREE" rev-parse HEAD)" = "$before_head" ]
  [ "$(git -C "$WORKTREE" status --porcelain)" = "$before_status" ]
}
