#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  UPDATER="$REPO_ROOT/scripts/sh/update-homebrew-casks.sh"
  TEST_BIN="$BATS_TEST_TMPDIR/bin"
  BREW_STATE="$BATS_TEST_TMPDIR/brew-state"
  COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"
  mkdir -p "$TEST_BIN" "$BREW_STATE"
  : >"$COMMAND_LOG"

  export BREW_STATE COMMAND_LOG
  export BREW_COMMAND="$TEST_BIN/brew"
  export NIX_COMMAND="$TEST_BIN/nix"
  export SLEEP_COMMAND="$TEST_BIN/sleep"
  export JQ_COMMAND="$(command -v jq)"
  export PGREP_COMMAND="$TEST_BIN/pgrep"
  export OPEN_COMMAND="$TEST_BIN/open"
  export DOTFILES_CASK_UPDATE_BACKOFF_SECONDS=2

  cat >"$BREW_COMMAND" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'brew %s\n' "$*" >>"$COMMAND_LOG"
command_name="${1:-}"
shift || true
cask=""
for argument in "$@"; do cask="$argument"; done
safe_cask="${cask//\//_}"
counter_file="$BREW_STATE/${command_name}-${safe_cask}.count"
count=0
[[ ! -f $counter_file ]] || count="$(cat "$counter_file")"
count=$((count + 1))
printf '%s\n' "$count" >"$counter_file"

case "$command_name" in
  list)
    [[ -f "$BREW_STATE/installed-$safe_cask" ]]
    ;;
  outdated)
    [[ ! -f "$BREW_STATE/outdated-$safe_cask" ]] || printf '%s\n' "$cask"
    ;;
  fetch)
    succeed_on="${BREW_FETCH_SUCCEED_ON:-1}"
    ((count >= succeed_on))
    ;;
  upgrade)
    succeed_on="${BREW_UPGRADE_SUCCEED_ON:-1}"
    ((count >= succeed_on)) || exit 1
    [[ ${BREW_KEEP_OUTDATED:-0} == 1 ]] || rm -f "$BREW_STATE/outdated-$safe_cask"
    ;;
  info)
    printf '%s\n' '{"casks":[{"artifacts":[]}]}'
    ;;
  *) exit 64 ;;
esac
EOF

  cat >"$NIX_COMMAND" <<'EOF'
#!/usr/bin/env bash
printf 'nix %s\n' "$*" >>"$COMMAND_LOG"
printf '%s' "${FAKE_NIX_CASKS:-}"
EOF
  cat >"$SLEEP_COMMAND" <<'EOF'
#!/usr/bin/env bash
printf 'sleep %s\n' "$*" >>"$COMMAND_LOG"
EOF
  printf '#!/usr/bin/env bash\nexit 1\n' >"$PGREP_COMMAND"
  printf '#!/usr/bin/env bash\nprintf "open %%s\\n" "$*" >>"$COMMAND_LOG"\n' >"$OPEN_COMMAND"
  chmod +x "$BREW_COMMAND" "$NIX_COMMAND" "$SLEEP_COMMAND" "$PGREP_COMMAND" "$OPEN_COMMAND"
}

install_cask() {
  local cask="${1//\//_}"
  touch "$BREW_STATE/installed-$cask"
}

mark_outdated() {
  local cask="${1//\//_}"
  touch "$BREW_STATE/outdated-$cask"
}

@test "updates only declared casks that are outdated under greedy semantics" {
  install_cask claude
  install_cask google-chrome
  mark_outdated claude

  run env DOTFILES_HOMEBREW_CASKS=$'claude\ngoogle-chrome' "$UPDATER"

  [ "$status" -eq 0 ]
  grep -q '^brew fetch --cask claude$' "$COMMAND_LOG"
  grep -q '^brew upgrade --cask --greedy claude$' "$COMMAND_LOG"
  ! grep -q '^brew fetch --cask google-chrome$' "$COMMAND_LOG"
  ! grep -q '^brew upgrade --cask --greedy google-chrome$' "$COMMAND_LOG"
}

@test "retries a failed fetch twice before the third attempt succeeds" {
  install_cask docker-desktop
  mark_outdated docker-desktop

  run env DOTFILES_HOMEBREW_CASKS=docker-desktop BREW_FETCH_SUCCEED_ON=3 "$UPDATER"

  [ "$status" -eq 0 ]
  [ "$(cat "$BREW_STATE/fetch-docker-desktop.count")" -eq 3 ]
  grep -q '^sleep 2$' "$COMMAND_LOG"
  grep -q '^sleep 4$' "$COMMAND_LOG"
}

@test "fails after three upgrade attempts" {
  install_cask claude
  mark_outdated claude

  run env DOTFILES_HOMEBREW_CASKS=claude BREW_UPGRADE_SUCCEED_ON=4 "$UPDATER"

  [ "$status" -ne 0 ]
  [ "$(cat "$BREW_STATE/upgrade-claude.count")" -eq 3 ]
  [[ "$output" == *"upgrade claude failed after 3 attempts"* ]]
}

@test "fails when a successful upgrade leaves a cask outdated" {
  install_cask visual-studio-code
  mark_outdated visual-studio-code

  run env DOTFILES_HOMEBREW_CASKS=visual-studio-code BREW_KEEP_OUTDATED=1 "$UPDATER"

  [ "$status" -ne 0 ]
  [[ "$output" == *"cask did not converge: visual-studio-code"* ]]
}

@test "fails when nix cannot evaluate the declared cask list" {
  cat >"$NIX_COMMAND" <<'EOF'
#!/usr/bin/env bash
exit 61
EOF
  chmod +x "$NIX_COMMAND"

  run env -u DOTFILES_HOMEBREW_CASKS "$UPDATER"

  [ "$status" -ne 0 ]
  ! grep -q '^brew ' "$COMMAND_LOG"
}
