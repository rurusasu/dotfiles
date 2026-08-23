# macOS Homebrew Cask Outdated Semantics Fix Implementation Plan

> **Status:** Historical plan. The standalone cask updater described here was superseded by nix-darwin's declarative Homebrew Bundle with `upgrade = true`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `nrs` correctly update named Homebrew casks when current Homebrew reports outdated items with exit status 1, including tap-qualified casks such as `stablyai/orca/orca`.

**Architecture:** Keep the existing per-cask updater and convergence loop. Centralize Homebrew's named-outdated tri-state interpretation in `check_outdated`, and separate the declared cask name used for update commands from the short Homebrew token used for installed-state and stdout matching.

**Tech Stack:** Bash 3.2-compatible shell, Homebrew CLI, Bats 1.5+, ShellCheck, Task, GitHub Actions.

## Global Constraints

- Exit status 1 plus stdout exactly equal to the short token means outdated.
- Exit status 0 plus empty stdout means current; status 0 plus the expected token remains a compatible outdated result.
- Status 1 with empty or unexpected stdout, and every status greater than 1, is a real failure.
- Use the short token for `brew list`; keep the declared name for `outdated`, `info`, `fetch`, and `upgrade`.
- Preserve retry, backoff, app restart, convergence, tap/formula/MAS, and `wezterm@nightly` behavior.
- Run the real `nrs` smoke test from macOS Terminal because upgrading Orca can terminate this session.
- Commit with `task commit DOTFILES_PATH="$PWD" -- "<message>"`.

## File Structure

- Modify `tests/bash/macos_homebrew_cask_update.bats`: model real named-query semantics and cover invalid output and tap-qualified identities.
- Modify `scripts/sh/update-homebrew-casks.sh`: normalize installed tokens and interpret status/output together.
- Reference `docs/superpowers/specs/2026-08-06-macos-homebrew-outdated-semantics-design.md`: approved contract.

---

### Task 1: Interpret Named `brew outdated` Results

**Files:**

- Modify: `tests/bash/macos_homebrew_cask_update.bats:24-67,100-238`
- Modify: `scripts/sh/update-homebrew-casks.sh:61-73`

**Interfaces:**

- Consumes: `brew outdated --cask --greedy <declared-name>` stdout and status.
- Produces: `check_outdated <declared-name>` setting `OUTDATED_STATUS=0` for a valid query and nonzero for a malformed or failed query; nonempty `OUTDATED_OUTPUT` remains the outdated flag.

- [ ] **Step 1: Make fake Homebrew reproduce named-query status 1**

Replace the fake `outdated)` branch with:

```bash
  outdated)
    [[ ${BREW_OUTDATED_FAIL:-0} != 1 ]] || exit 65
    [[ ${BREW_OUTDATED_EMPTY_STATUS_ONE:-0} != 1 ]] || exit 1
    if [[ -f "$BREW_STATE/outdated-$safe_cask" ]]; then
      printf '%s\n' "${BREW_OUTDATED_OUTPUT_OVERRIDE:-$cask}"
      exit "${BREW_OUTDATED_EXIT_STATUS:-1}"
    fi
    ;;
```

- [ ] **Step 2: Add exact status/output matrix tests**

Add after the existing Homebrew failure test:

```bash
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
```

- [ ] **Step 3: Prove the new realistic happy path is red**

Run `bats tests/bash/macos_homebrew_cask_update.bats`.

Expected: existing outdated-cask happy paths fail because status 1 is still treated as a command failure.

- [ ] **Step 4: Implement combined status/output interpretation**

Replace `check_outdated` with:

```bash
check_outdated() {
  local cask="$1" command_status
  OUTDATED_OUTPUT=""
  OUTDATED_STATUS=0

  if OUTDATED_OUTPUT=$("$BREW_COMMAND" outdated --cask --greedy "$cask"); then
    command_status=0
  else
    command_status=$?
  fi

  if ((command_status == 0)) && [[ -z $OUTDATED_OUTPUT ]]; then
    return
  fi
  if ((command_status <= 1)) && [[ $OUTDATED_OUTPUT == "$cask" ]]; then
    return
  fi

  OUTDATED_STATUS=$command_status
  ((OUTDATED_STATUS != 0)) || OUTDATED_STATUS=1
  printf '[macos-cask-update] failed to check outdated status for %s (status %d)\n' \
    "$cask" "$command_status" >&2
}
```

- [ ] **Step 5: Prove the status semantics are green**

Run `bats tests/bash/macos_homebrew_cask_update.bats`.

Expected: 16 tests pass, including status 1 outdated, status 0 compatibility, invalid status 1 output, and status 65 failure.

- [ ] **Step 6: Commit Task 1**

```bash
task commit DOTFILES_PATH="$PWD" -- "fix: handle Homebrew outdated exit status"
```

Expected: formatter and pre-commit hooks pass; only Task 1 updater and Bats changes are committed.

---

### Task 2: Normalize Tap-Qualified Cask Identity

**Files:**

- Modify: `tests/bash/macos_homebrew_cask_update.bats:24-67,90-116`
- Modify: `scripts/sh/update-homebrew-casks.sh:57-73,134-172`

**Interfaces:**

- Consumes: a declared name such as `stablyai/orca/orca`.
- Produces: `cask_token <declared-name>` printing `orca`; installed checks use it, while update commands retain the declared name.

- [ ] **Step 1: Add a tap-qualified regression test**

```bash
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
```

- [ ] **Step 2: Make fake Homebrew state short-token based**

Replace fake state-key derivation with:

```bash
cask=""
for argument in "$@"; do cask="$argument"; done
cask_token="${cask##*/}"
safe_cask="${cask_token//\//_}"
```

Change the outdated output default to:

```bash
printf '%s\n' "${BREW_OUTDATED_OUTPUT_OVERRIDE:-$cask_token}"
```

- [ ] **Step 3: Prove the tap-qualified path is red**

Run `bats --filter "tap-qualified" tests/bash/macos_homebrew_cask_update.bats`.

Expected: FAIL because the updater asks `brew list` for the full tap-qualified name.

- [ ] **Step 4: Normalize installed and stdout identities once**

Insert and use:

```bash
cask_token() {
  printf '%s\n' "${1##*/}"
}

is_installed() {
  local token
  token="$(cask_token "$1")"
  [[ -n $token ]] && "$BREW_COMMAND" list --cask --versions "$token" >/dev/null 2>&1
}
```

Change `check_outdated` locals and comparison to:

```bash
local cask="$1" token command_status
token="$(cask_token "$cask")"

if ((command_status <= 1)) && [[ -n $token && $OUTDATED_OUTPUT == "$token" ]]; then
  return
fi
```

The loops keep passing the declared name. Thus `list` receives `orca`, while `outdated`, `info`, `fetch`, and `upgrade` receive `stablyai/orca/orca`.

- [ ] **Step 5: Prove the full focused suite is green**

Run `bats tests/bash/macos_homebrew_cask_update.bats`.

Expected: 18 tests pass, the tap-qualified command log matches the regression assertions, and an empty short token fails before invoking `brew list`.

- [ ] **Step 6: Commit Task 2**

```bash
task commit DOTFILES_PATH="$PWD" -- "fix: normalize tap-qualified cask tokens"
```

Expected: formatter and pre-commit hooks pass; the working tree is clean.

---

### Task 3: Validate, Publish, Merge, and Verify on macOS

**Files:**

- Verify: `scripts/sh/update-homebrew-casks.sh`
- Verify: `tests/bash/macos_homebrew_cask_update.bats`
- Verify: `tests/bash/macos_config.bats`

**Interfaces:**

- Consumes: both implementation commits and GitHub Actions.
- Produces: merged PR, fast-forwarded local `main`, successful `nrs`, current declared casks, and a ready Docker daemon.

- [ ] **Step 1: Run compatibility and static checks**

```bash
/bin/bash -n scripts/sh/update-homebrew-casks.sh
shellcheck scripts/sh/update-homebrew-casks.sh tests/bash/macos_homebrew_cask_update.bats
```

Expected: both commands exit 0 with Bash 3.2-compatible syntax.

- [ ] **Step 2: Run focused tests**

```bash
bats tests/bash/macos_homebrew_cask_update.bats
bats tests/bash/macos_config.bats
```

Expected: 18 updater tests and all macOS configuration contract tests pass.

- [ ] **Step 3: Run complete validation**

```bash
task test:bash DOTFILES_PATH="$PWD"
pre-commit run --all-files
```

Expected: 169 Bash tests and every pre-commit hook pass.

- [ ] **Step 4: Review final branch scope**

```bash
git diff --check main...HEAD
git diff --stat main...HEAD
git diff main...HEAD -- scripts/sh/update-homebrew-casks.sh tests/bash/macos_homebrew_cask_update.bats
git status --short --branch
```

Expected: only the approved spec, plan, updater, and Bats changes; no whitespace errors; clean worktree.

- [ ] **Step 5: Push and open a ready PR**

```bash
git push -u origin rurusasu/macos-homebrew-outdated-semantics
gh pr create --base main --head rurusasu/macos-homebrew-outdated-semantics \
  --title "fix: handle Homebrew named outdated semantics" \
  --body-file /tmp/macos-homebrew-outdated-semantics-pr.md
```

The body records both root causes, the status/output matrix, tap-qualified behavior, and validation results. It is not a draft because the user requested an open PR.

- [ ] **Step 6: Wait for Actions and merge only on success**

```bash
gh pr checks --watch --fail-fast
gh pr merge --merge
```

Expected: every reported check succeeds before merge. A failure is diagnosed and fixed instead of bypassed.

- [ ] **Step 7: Fast-forward local `main`**

```bash
git -C /Users/ktome1995/Program/dotfiles pull --ff-only origin main
git -C /Users/ktome1995/Program/dotfiles status --short --branch
```

Expected: local `main` is clean at the merged result.

- [ ] **Step 8: Run `nrs` from macOS Terminal**

Run outside Orca:

```bash
cd /Users/ktome1995/Program/dotfiles && nrs
```

If `sudo` requests a password, pause for user input. Expected: all five declared desktop casks are checked without false failures, updater convergence succeeds, the macOS installer completes, and Docker Desktop restarts.

- [ ] **Step 9: Verify real-machine convergence**

```bash
for cask in claude docker-desktop google-chrome stablyai/orca/orca visual-studio-code; do
  output="$(/opt/homebrew/bin/brew outdated --cask --greedy "$cask" 2>&1)"
  status=$?
  [[ $status -eq 0 && -z $output ]] || {
    printf '%s: status=%d output=%s\n' "$cask" "$status" "$output" >&2
    exit 1
  }
done
/opt/homebrew/bin/brew list --cask --versions orca
docker info >/dev/null
```

Expected: every declared cask query returns status 0 with empty stdout, Orca is installed under its short token, and Docker is ready.
