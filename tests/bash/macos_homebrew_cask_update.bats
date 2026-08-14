#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

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
  JQ_COMMAND="$(command -v jq)"
  export JQ_COMMAND
  export PGREP_COMMAND="$TEST_BIN/pgrep"
  export PKILL_COMMAND="$TEST_BIN/pkill"
  export PS_COMMAND="$TEST_BIN/ps"
  export KILL_COMMAND="$TEST_BIN/kill"
  export OPEN_COMMAND="$TEST_BIN/open"
  APP_PROCESS_EXITED_STATE="$BATS_TEST_TMPDIR/app-process-exited"
  export APP_PROCESS_EXITED_STATE
  export DOTFILES_CASK_UPDATE_BACKOFF_SECONDS=2

  cat >"$BREW_COMMAND" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'brew %s\n' "$*" >>"$COMMAND_LOG"
command_name="${1:-}"
shift || true
cask=""
for argument in "$@"; do cask="$argument"; done
cask_token="${cask##*/}"
safe_cask="${cask_token//\//_}"
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
    [[ ${BREW_OUTDATED_FAIL:-0} != 1 ]] || exit 65
    [[ ${BREW_OUTDATED_EMPTY_STATUS_ONE:-0} != 1 ]] || exit 1
    if [[ -f "$BREW_STATE/outdated-$safe_cask" ]]; then
      printf '%s\n' "${BREW_OUTDATED_OUTPUT_OVERRIDE:-$cask_token}"
      exit "${BREW_OUTDATED_EXIT_STATUS:-1}"
    fi
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
    [[ ${BREW_INFO_FAIL:-0} != 1 ]] || exit 66
    cask="${2:-}"
    if [[ $cask == claude ]]; then
      printf '%s\n' '{"casks":[{"artifacts":[{"app":["Claude.app"],"target":"/Applications/Claude.app"}]}]}'
    elif [[ $cask == 1password ]]; then
      printf '%s\n' '{"casks":[{"artifacts":[{"app":["1Password.app"],"target":"/Applications/1Password.app"}]}]}'
    elif [[ $cask == thebrowsercompany-dia ]]; then
      printf '%s\n' '{"casks":[{"artifacts":[{"app":["Dia.app"],"target":"/Applications/Dia.app"}]}]}'
    else
      printf '%s\n' '{"casks":[{"artifacts":[]}]}'
    fi
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
  cat >"$PGREP_COMMAND" <<'EOF'
#!/usr/bin/env bash
printf 'pgrep %s\n' "$*" >>"$COMMAND_LOG"
[[ "$*" == *"${FAKE_RUNNING_APP:-never}"* ]] || exit 1
[[ ! -f $APP_PROCESS_EXITED_STATE ]] || exit 1
printf '%s\n' "${FAKE_PROCESS_ID:-4242}"
EOF
  cat >"$PKILL_COMMAND" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'pkill %s\n' "$*" >>"$COMMAND_LOG"
[[ "$*" == *"${FAKE_RUNNING_APP:-never}"* ]] || exit 1
[[ ! -f $APP_PROCESS_EXITED_STATE ]] || exit 1

case "$*" in
*-TERM*)
  if [[ ${FAKE_APP_EXITS_DURING_TERM:-0} == 1 ]]; then
    : >"$APP_PROCESS_EXITED_STATE"
    exit 1
  fi
  [[ ${FAKE_APP_IGNORES_TERM:-0} == 1 ]] || : >"$APP_PROCESS_EXITED_STATE"
  ;;
*-KILL*)
  [[ ${FAKE_APP_IGNORES_KILL:-0} == 1 ]] || : >"$APP_PROCESS_EXITED_STATE"
  ;;
*) exit 64 ;;
esac
EOF
  cat >"$PS_COMMAND" <<'EOF'
#!/usr/bin/env bash
printf 'ps %s\n' "$*" >>"$COMMAND_LOG"
[[ ! -f $APP_PROCESS_EXITED_STATE ]] || exit 1
printf '%s\n' "${FAKE_PROCESS_EXECUTABLE:-${FAKE_RUNNING_APP:-}/Contents/MacOS/app}"
EOF
  cat >"$KILL_COMMAND" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'kill %s\n' "$*" >>"$COMMAND_LOG"
[[ ! -f $APP_PROCESS_EXITED_STATE ]] || exit 1

case "$*" in
*-TERM*)
  if [[ ${FAKE_APP_EXITS_DURING_TERM:-0} == 1 ]]; then
    : >"$APP_PROCESS_EXITED_STATE"
    exit 1
  fi
  [[ ${FAKE_APP_IGNORES_TERM:-0} == 1 ]] || : >"$APP_PROCESS_EXITED_STATE"
  ;;
*-KILL*)
  [[ ${FAKE_APP_IGNORES_KILL:-0} == 1 ]] || : >"$APP_PROCESS_EXITED_STATE"
  ;;
*) exit 64 ;;
esac
EOF
  cat >"$OPEN_COMMAND" <<'EOF'
#!/usr/bin/env bash
printf 'open %s\n' "$*" >>"$COMMAND_LOG"
EOF
  chmod +x "$BREW_COMMAND" "$NIX_COMMAND" "$SLEEP_COMMAND" "$PGREP_COMMAND" "$PKILL_COMMAND" \
    "$PS_COMMAND" "$KILL_COMMAND" "$OPEN_COMMAND"
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
  install_cask undeclared-cask
  mark_outdated claude
  mark_outdated undeclared-cask

  run env DOTFILES_HOMEBREW_CASKS=$'claude\ngoogle-chrome' "$UPDATER"

  [ "$status" -eq 0 ]
  grep -q '^brew fetch --cask claude$' "$COMMAND_LOG"
  grep -q '^brew upgrade --cask --greedy claude$' "$COMMAND_LOG"
  run ! grep -q '^brew fetch --cask google-chrome$' "$COMMAND_LOG"
  run ! grep -q '^brew upgrade --cask --greedy google-chrome$' "$COMMAND_LOG"
  [ "$(grep '^brew outdated ' "$COMMAND_LOG")" = $'brew outdated --cask --greedy claude\nbrew outdated --cask --greedy google-chrome\nbrew outdated --cask --greedy claude\nbrew outdated --cask --greedy google-chrome' ]
  run ! grep -q '^brew .* undeclared-cask$' "$COMMAND_LOG"
}

@test "updates a tap-qualified cask using its short installed token" {
  install_cask orca
  mark_outdated orca
  run env DOTFILES_HOMEBREW_CASKS=stablyai/orca/orca "$UPDATER"

  [ "$status" -eq 0 ]
  grep -q '^brew list --cask --versions orca$' "$COMMAND_LOG"
  grep -q '^brew outdated --cask --greedy stablyai/orca/orca$' "$COMMAND_LOG"
  grep -q '^brew info --cask stablyai/orca/orca --json=v2$' "$COMMAND_LOG"
  grep -q '^brew fetch --cask stablyai/orca/orca$' "$COMMAND_LOG"
  grep -q '^brew upgrade --cask --greedy stablyai/orca/orca$' "$COMMAND_LOG"
}

@test "rejects a declared cask without a short token" {
  run env DOTFILES_HOMEBREW_CASKS=stablyai/orca/ "$UPDATER"

  [ "$status" -ne 0 ]
  [[ "$output" == *"declared cask is not installed: stablyai/orca/"* ]]
  run ! grep -q '^brew list ' "$COMMAND_LOG"
  run ! grep -q '^brew fetch ' "$COMMAND_LOG"
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

@test "reopens an application that was running before a successful upgrade" {
  install_cask claude
  mark_outdated claude

  run env DOTFILES_HOMEBREW_CASKS=claude FAKE_RUNNING_APP=/Applications/Claude.app "$UPDATER"

  [ "$status" -eq 0 ]
  grep -q '^open -gj /Applications/Claude.app$' "$COMMAND_LOG"
  pgrep_line="$(grep -n -m1 '^pgrep ' "$COMMAND_LOG" | cut -d: -f1)"
  fetch_line="$(grep -n -m1 '^brew fetch ' "$COMMAND_LOG" | cut -d: -f1)"
  upgrade_line="$(grep -n -m1 '^brew upgrade ' "$COMMAND_LOG" | cut -d: -f1)"
  open_line="$(grep -n -m1 '^open ' "$COMMAND_LOG" | cut -d: -f1)"
  [ "$pgrep_line" -lt "$fetch_line" ]
  [ "$upgrade_line" -lt "$open_line" ]
}

@test "sends TERM to a running application before upgrading and reopens it after the update" {
  install_cask claude
  mark_outdated claude

  run env DOTFILES_HOMEBREW_CASKS=claude FAKE_RUNNING_APP=/Applications/Claude.app "$UPDATER"

  [ "$status" -eq 0 ]
  grep -q '^kill -TERM 4242$' "$COMMAND_LOG"
  grep -q '^open -gj /Applications/Claude.app$' "$COMMAND_LOG"
  initial_pgrep_line="$(grep -n -m1 '^pgrep ' "$COMMAND_LOG" | cut -d: -f1)"
  terminate_line="$(grep -n -m1 '^kill -TERM ' "$COMMAND_LOG" | cut -d: -f1)"
  fetch_line="$(grep -n -m1 '^brew fetch ' "$COMMAND_LOG" | cut -d: -f1)"
  upgrade_line="$(grep -n -m1 '^brew upgrade ' "$COMMAND_LOG" | cut -d: -f1)"
  open_line="$(grep -n -m1 '^open ' "$COMMAND_LOG" | cut -d: -f1)"
  [ "$initial_pgrep_line" -lt "$terminate_line" ]
  [ "$terminate_line" -lt "$fetch_line" ]
  [ "$upgrade_line" -lt "$open_line" ]
}

@test "force kills an application helper that remains after TERM" {
  install_cask 1password
  mark_outdated 1password

  run env DOTFILES_HOMEBREW_CASKS=1password FAKE_RUNNING_APP=/Applications/1Password.app \
    FAKE_APP_IGNORES_TERM=1 "$UPDATER"

  [ "$status" -eq 0 ]
  grep -q '^kill -KILL 4242$' "$COMMAND_LOG"
  grep -q '^brew fetch --cask 1password$' "$COMMAND_LOG"
  grep -q '^brew upgrade --cask --greedy 1password$' "$COMMAND_LOG"
  grep -q '^open -gj /Applications/1Password.app$' "$COMMAND_LOG"
}

@test "does not upgrade when an application survives KILL" {
  install_cask claude
  mark_outdated claude

  run env DOTFILES_HOMEBREW_CASKS=claude FAKE_RUNNING_APP=/Applications/Claude.app \
    FAKE_APP_IGNORES_TERM=1 FAKE_APP_IGNORES_KILL=1 "$UPDATER"

  [ "$status" -ne 0 ]
  [[ "$output" == *"application did not exit: /Applications/Claude.app"* ]]
  grep -q '^kill -KILL 4242$' "$COMMAND_LOG"
  run ! grep -q '^brew fetch ' "$COMMAND_LOG"
  run ! grep -q '^brew upgrade ' "$COMMAND_LOG"
}

@test "force kills an app that ignores TERM before upgrading and reopening it" {
  install_cask thebrowsercompany-dia
  mark_outdated thebrowsercompany-dia

  run env DOTFILES_HOMEBREW_CASKS=thebrowsercompany-dia \
    FAKE_RUNNING_APP=/Applications/Dia.app FAKE_APP_IGNORES_TERM=1 "$UPDATER"

  [ "$status" -eq 0 ]
  grep -q '^kill -TERM 4242$' "$COMMAND_LOG"
  grep -q '^kill -KILL 4242$' "$COMMAND_LOG"
  grep -q '^brew fetch --cask thebrowsercompany-dia$' "$COMMAND_LOG"
  grep -q '^brew upgrade --cask --greedy thebrowsercompany-dia$' "$COMMAND_LOG"
  grep -q '^open -gj /Applications/Dia.app$' "$COMMAND_LOG"
}

@test "does not KILL an app that exits after TERM" {
  install_cask claude
  mark_outdated claude

  run env DOTFILES_HOMEBREW_CASKS=claude FAKE_RUNNING_APP=/Applications/Claude.app "$UPDATER"

  [ "$status" -eq 0 ]
  grep -q '^kill -TERM 4242$' "$COMMAND_LOG"
  run ! grep -q '^kill -KILL ' "$COMMAND_LOG"
}

@test "does not signal a process that only has an app bundle path in its arguments" {
  install_cask claude
  mark_outdated claude

  run env DOTFILES_HOMEBREW_CASKS=claude FAKE_RUNNING_APP=/Applications/Claude.app \
    FAKE_PROCESS_EXECUTABLE=/usr/bin/codesign "$UPDATER"

  [ "$status" -eq 0 ]
  grep -q '^ps -p ' "$COMMAND_LOG"
  run ! grep -q '^pkill ' "$COMMAND_LOG"
  run ! grep -q '^kill ' "$COMMAND_LOG"
  run ! grep -q '^open ' "$COMMAND_LOG"
  grep -q '^brew fetch --cask claude$' "$COMMAND_LOG"
  grep -q '^brew upgrade --cask --greedy claude$' "$COMMAND_LOG"
}

@test "continues when an app exits while TERM is being sent" {
  install_cask claude
  mark_outdated claude

  run env DOTFILES_HOMEBREW_CASKS=claude FAKE_RUNNING_APP=/Applications/Claude.app \
    FAKE_APP_EXITS_DURING_TERM=1 "$UPDATER"

  [ "$status" -eq 0 ]
  grep -q '^kill -TERM 4242$' "$COMMAND_LOG"
  grep -q '^brew fetch --cask claude$' "$COMMAND_LOG"
  run ! grep -q '^kill -KILL ' "$COMMAND_LOG"
}

@test "reopens a running application after upgrade retries are exhausted" {
  install_cask claude
  mark_outdated claude

  run env DOTFILES_HOMEBREW_CASKS=claude FAKE_RUNNING_APP=/Applications/Claude.app \
    BREW_UPGRADE_SUCCEED_ON=4 "$UPDATER"

  [ "$status" -ne 0 ]
  grep -q '^open -gj /Applications/Claude.app$' "$COMMAND_LOG"
}

@test "does not open an application that was not running" {
  install_cask claude
  mark_outdated claude

  run env DOTFILES_HOMEBREW_CASKS=claude "$UPDATER"

  [ "$status" -eq 0 ]
  run ! grep -q '^open ' "$COMMAND_LOG"
}

@test "fails without upgrading when brew info cannot describe app artifacts" {
  install_cask claude
  mark_outdated claude

  run env DOTFILES_HOMEBREW_CASKS=claude BREW_INFO_FAIL=1 "$UPDATER"

  [ "$status" -ne 0 ]
  run ! grep -q '^brew fetch ' "$COMMAND_LOG"
  run ! grep -q '^brew upgrade ' "$COMMAND_LOG"
}

@test "fails without upgrading when jq cannot parse app artifacts" {
  install_cask claude
  mark_outdated claude
  jq_failure="$TEST_BIN/jq-failure"
  cat >"$jq_failure" <<'EOF'
#!/usr/bin/env bash
exit 67
EOF
  chmod +x "$jq_failure"

  run env DOTFILES_HOMEBREW_CASKS=claude JQ_COMMAND="$jq_failure" "$UPDATER"

  [ "$status" -ne 0 ]
  run ! grep -q '^brew fetch ' "$COMMAND_LOG"
  run ! grep -q '^brew upgrade ' "$COMMAND_LOG"
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
  run ! grep -q '^brew ' "$COMMAND_LOG"
}

@test "fails when brew cannot determine whether a declared cask is outdated" {
  install_cask claude

  run env DOTFILES_HOMEBREW_CASKS=claude BREW_OUTDATED_FAIL=1 "$UPDATER"

  [ "$status" -ne 0 ]
  [[ "$output" == *"failed to check outdated status for claude (status 65)"* ]]
  run ! grep -q '^brew fetch ' "$COMMAND_LOG"
  run ! grep -q '^brew upgrade ' "$COMMAND_LOG"
}

@test "accepts exit status zero with a matching outdated token for compatibility" {
  install_cask claude
  mark_outdated claude
  run env DOTFILES_HOMEBREW_CASKS=claude BREW_OUTDATED_EXIT_STATUS=0 "$UPDATER"
  [ "$status" -eq 0 ]
  grep -q '^brew upgrade --cask --greedy claude$' "$COMMAND_LOG"
}

@test "rejects exit status one without an outdated token" {
  install_cask claude
  run env DOTFILES_HOMEBREW_CASKS=claude BREW_OUTDATED_EMPTY_STATUS_ONE=1 "$UPDATER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"failed to check outdated status for claude (status 1)"* ]]
  run ! grep -q '^brew fetch ' "$COMMAND_LOG"
}

@test "rejects exit status one with an unexpected outdated token" {
  install_cask claude
  mark_outdated claude
  run env DOTFILES_HOMEBREW_CASKS=claude BREW_OUTDATED_OUTPUT_OVERRIDE=other-cask "$UPDATER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"failed to check outdated status for claude (status 1)"* ]]
  run ! grep -q '^brew fetch ' "$COMMAND_LOG"
}

@test "rejects exit status zero with an unexpected outdated token" {
  install_cask claude
  mark_outdated claude
  run env DOTFILES_HOMEBREW_CASKS=claude BREW_OUTDATED_EXIT_STATUS=0 \
    BREW_OUTDATED_OUTPUT_OVERRIDE=other-cask "$UPDATER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"failed to check outdated status for claude (status 0)"* ]]
  run ! grep -q '^brew fetch ' "$COMMAND_LOG"
  run ! grep -q '^brew upgrade ' "$COMMAND_LOG"
}

@test "rejects exit status greater than one with a matching outdated token" {
  install_cask claude
  mark_outdated claude
  run env DOTFILES_HOMEBREW_CASKS=claude BREW_OUTDATED_EXIT_STATUS=65 "$UPDATER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"failed to check outdated status for claude (status 65)"* ]]
  run ! grep -q '^brew fetch ' "$COMMAND_LOG"
  run ! grep -q '^brew upgrade ' "$COMMAND_LOG"
}

@test "rejects more than three update attempts before invoking brew" {
  install_cask claude
  mark_outdated claude

  run env DOTFILES_HOMEBREW_CASKS=claude \
    DOTFILES_CASK_UPDATE_ATTEMPTS=4 BREW_UPGRADE_SUCCEED_ON=4 "$UPDATER"

  [ "$status" -ne 0 ]
  [[ "$output" == *"DOTFILES_CASK_UPDATE_ATTEMPTS must be an integer between 1 and 3: 4"* ]]
  run ! grep -q '^brew ' "$COMMAND_LOG"
}

@test "rejects a backoff other than two seconds before invoking brew" {
  install_cask claude
  mark_outdated claude

  run env DOTFILES_HOMEBREW_CASKS=claude DOTFILES_CASK_UPDATE_BACKOFF_SECONDS=3 "$UPDATER"

  [ "$status" -ne 0 ]
  [[ "$output" == *"DOTFILES_CASK_UPDATE_BACKOFF_SECONDS must be 2: 3"* ]]
  run ! grep -q '^brew ' "$COMMAND_LOG"
}
