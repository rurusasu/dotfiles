# macOS Homebrew Cask Updates Implementation Plan

> **Status:** Superseded on 2026-08-22. The dedicated updater and WezTerm archive installer described here were removed; nix-darwin's declarative Homebrew Bundle now owns cask installation and upgrades.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `nrs` reliably update every dotfiles-declared macOS Homebrew cask, including greedy casks, with bounded retries, final convergence checks, and restart of applications that were running before the update.

**Architecture:** Keep nix-darwin responsible for Homebrew metadata and missing-cask installation, but disable its implicit upgrade pass. Add a testable Bash updater that reads the evaluated nix-darwin cask list, updates each outdated cask explicitly, and is invoked by `install-macos.sh` between nix-darwin activation and Docker runtime setup.

**Tech Stack:** Bash 3.2-compatible shell, Bats, Nix/nix-darwin, Homebrew Bundle/Cask, jq, Taskfile, pre-commit

## Global Constraints

- Support Apple Silicon macOS 26 or later; do not change Linux, NixOS, WSL, or Windows behavior.
- Update only casks declared by `darwinConfigurations.macos.config.homebrew.casks`.
- Treat versioned, `auto_updates`, and `version = :latest` casks as convergence targets by using greedy checks.
- Attempt each fetch or upgrade at most 3 times, waiting 2 seconds and then 4 seconds between attempts.
- Preserve the existing dedicated `wezterm@nightly` archive installer; never pass it to the general cask updater.
- Let Homebrew perform application termination; reopen only applications that were running before the update.
- A cask-list evaluation error, exhausted retry, or remaining outdated cask must make `nrs` return non-zero.
- Keep command dependencies injectable so automated tests never modify real Homebrew state or launch/quit real GUI applications.
- Use `task commit DOTFILES_PATH="$PWD" -- "<message>"` for every implementation commit.

---

### Task 1: Explicit cask discovery, update, retry, and convergence

**Files:**

- Create: `scripts/sh/update-homebrew-casks.sh`
- Create: `tests/bash/macos_homebrew_cask_update.bats`

**Interfaces:**

- Consumes: `DOTFILES_ROOT`, `DOTFILES_HOMEBREW_CASKS`, `BREW_COMMAND`, `NIX_COMMAND`, `SLEEP_COMMAND`, `DOTFILES_CASK_UPDATE_ATTEMPTS`, and `DOTFILES_CASK_UPDATE_BACKOFF_SECONDS`.
- Produces: an executable updater whose exit code is zero only when every declared, installed cask is no longer outdated under `--greedy` semantics.

- [ ] **Step 1: Create a fake Homebrew fixture and failing happy-path test**

Create `tests/bash/macos_homebrew_cask_update.bats` with a real invocation of the not-yet-created script. The fake only replaces external Homebrew/Nix/sleep boundaries; assertions target the updater's exit code and command sequence.

```bash
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
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
bats tests/bash/macos_homebrew_cask_update.bats
```

Expected: FAIL because `scripts/sh/update-homebrew-casks.sh` does not exist.

- [ ] **Step 3: Implement the smallest updater that passes the happy path**

Create `scripts/sh/update-homebrew-casks.sh` with Bash 3.2-compatible loops and no arrays that require Bash 4.

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="${DOTFILES_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
BREW_COMMAND="${BREW_COMMAND:-/opt/homebrew/bin/brew}"
NIX_COMMAND="${NIX_COMMAND:-nix}"
SLEEP_COMMAND="${SLEEP_COMMAND:-sleep}"
ATTEMPTS="${DOTFILES_CASK_UPDATE_ATTEMPTS:-3}"
BACKOFF_SECONDS="${DOTFILES_CASK_UPDATE_BACKOFF_SECONDS:-2}"
export HOMEBREW_NO_AUTO_UPDATE=1

temporary_directory="$(mktemp -d)"
cask_file="$temporary_directory/casks"
failure_file="$temporary_directory/failures"
: >"$failure_file"

cleanup() {
  rm -rf "$temporary_directory"
}
trap cleanup EXIT

load_casks() {
  if [[ ${DOTFILES_HOMEBREW_CASKS+x} == x ]]; then
    printf '%s' "$DOTFILES_HOMEBREW_CASKS"
    return
  fi

  "$NIX_COMMAND" eval --impure --raw \
    "$ROOT#darwinConfigurations.macos.config.homebrew.casks" \
    --apply 'casks: builtins.concatStringsSep "\n" (builtins.map (cask: if builtins.isString cask then cask else cask.name) casks)'
}

is_installed() {
  "$BREW_COMMAND" list --cask --versions "$1" >/dev/null 2>&1
}

is_outdated() {
  [[ -n $("$BREW_COMMAND" outdated --cask --greedy "$1") ]]
}

retry_command() {
  local label="$1"
  shift
  local attempt delay
  for ((attempt = 1; attempt <= ATTEMPTS; attempt++)); do
    if "$@"; then
      return 0
    fi
    if ((attempt < ATTEMPTS)); then
      delay=$((BACKOFF_SECONDS * attempt))
      printf '[macos-cask-update] %s failed (attempt %d/%d); retrying in %ds\n' \
        "$label" "$attempt" "$ATTEMPTS" "$delay" >&2
      "$SLEEP_COMMAND" "$delay"
    fi
  done
  printf '[macos-cask-update] %s failed after %d attempts\n' "$label" "$ATTEMPTS" >&2
  return 1
}

load_casks >"$cask_file"
[[ -s $cask_file ]] || {
  printf '[macos-cask-update] evaluated cask list is empty\n' >&2
  exit 1
}

while IFS= read -r cask || [[ -n $cask ]]; do
  [[ -n $cask ]] || continue
  if ! is_installed "$cask"; then
    printf '[macos-cask-update] declared cask is not installed: %s\n' "$cask" >&2
    printf '%s\n' "$cask" >>"$failure_file"
    continue
  fi
  is_outdated "$cask" || continue
  if ! retry_command "fetch $cask" "$BREW_COMMAND" fetch --cask "$cask"; then
    printf '%s\n' "$cask" >>"$failure_file"
    continue
  fi
  if ! retry_command "upgrade $cask" "$BREW_COMMAND" upgrade --cask --greedy "$cask"; then
    printf '%s\n' "$cask" >>"$failure_file"
  fi
done <"$cask_file"

while IFS= read -r cask || [[ -n $cask ]]; do
  [[ -n $cask ]] || continue
  if ! is_installed "$cask" || is_outdated "$cask"; then
    printf '[macos-cask-update] cask did not converge: %s\n' "$cask" >&2
    grep -Fxq "$cask" "$failure_file" || printf '%s\n' "$cask" >>"$failure_file"
  fi
done <"$cask_file"

[[ ! -s $failure_file ]]
```

Make the new entrypoint executable:

```bash
chmod +x scripts/sh/update-homebrew-casks.sh
```

- [ ] **Step 4: Add failing retry and convergence tests**

Append tests with literal expectations that catch missing retry limits, wrong backoff, and missing post-upgrade verification.

```bash
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
```

- [ ] **Step 5: Run focused tests and make them GREEN**

Run:

```bash
bats tests/bash/macos_homebrew_cask_update.bats
bash -n scripts/sh/update-homebrew-casks.sh
shellcheck scripts/sh/update-homebrew-casks.sh
```

Expected: all updater Bats tests pass; syntax and ShellCheck return zero.

- [ ] **Step 6: Commit the core updater**

```bash
task commit DOTFILES_PATH="$PWD" -- "feat: update declared macOS casks reliably"
```

Expected: formatter, pre-commit hooks, and commit succeed.

---

### Task 2: Restart applications that were running before upgrade

**Files:**

- Modify: `scripts/sh/update-homebrew-casks.sh`
- Modify: `tests/bash/macos_homebrew_cask_update.bats`

**Interfaces:**

- Consumes: Task 1 updater plus `JQ_COMMAND`, `PGREP_COMMAND`, and `OPEN_COMMAND`.
- Produces: `record_running_apps <cask>` and `reopen_apps`, with cleanup preserving the updater's original exit status.

- [ ] **Step 1: Extend the fake boundaries and write failing restart tests**

Change the fake `brew info` branch so `claude` exposes the complete app artifact shape returned by real Homebrew.

```bash
  info)
    if [[ $cask == claude ]]; then
      printf '%s\n' '{"casks":[{"artifacts":[{"uninstall":[{"quit":["com.anthropic.claudefordesktop"]}]},{"app":["Claude.app"],"target":"/Applications/Claude.app"}]}]}'
    else
      printf '%s\n' '{"casks":[{"artifacts":[]}]}'
    fi
    ;;
```

Make fake `pgrep` return zero only for the configured running application, then add success and failure cases.

```bash
cat >"$PGREP_COMMAND" <<'EOF'
#!/usr/bin/env bash
printf 'pgrep %s\n' "$*" >>"$COMMAND_LOG"
[[ "$*" == *"${FAKE_RUNNING_APP:-never}"* ]]
EOF

@test "reopens an application that was running before a successful upgrade" {
  install_cask claude
  mark_outdated claude

  run env DOTFILES_HOMEBREW_CASKS=claude FAKE_RUNNING_APP=/Applications/Claude.app "$UPDATER"

  [ "$status" -eq 0 ]
  grep -q '^open -gj /Applications/Claude.app$' "$COMMAND_LOG"
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
  ! grep -q '^open ' "$COMMAND_LOG"
}
```

- [ ] **Step 2: Run the new tests and verify RED**

Run:

```bash
bats tests/bash/macos_homebrew_cask_update.bats
```

Expected: the two running-app tests FAIL because no app paths are recorded or reopened.

- [ ] **Step 3: Add app artifact discovery and exit-trap restart behavior**

Add command defaults and a restart file near the updater's existing setup.

```bash
JQ_COMMAND="${JQ_COMMAND:-jq}"
PGREP_COMMAND="${PGREP_COMMAND:-pgrep}"
OPEN_COMMAND="${OPEN_COMMAND:-open}"
restart_file="$temporary_directory/restart-apps"
: >"$restart_file"
```

Add these functions before the main update loop.

```bash
record_running_apps() {
  local cask="$1" app_path
  while IFS= read -r app_path || [[ -n $app_path ]]; do
    [[ -n $app_path ]] || continue
    if "$PGREP_COMMAND" -f "$app_path/Contents/" >/dev/null 2>&1; then
      grep -Fxq "$app_path" "$restart_file" || printf '%s\n' "$app_path" >>"$restart_file"
    fi
  done < <(
    "$BREW_COMMAND" info --cask "$cask" --json=v2 |
      "$JQ_COMMAND" -r '
        .casks[0].artifacts[]?
        | select(has("app"))
        | if has("target") then .target else .app[] | "/Applications/" + . end
      '
  )
}

reopen_apps() {
  local app_path
  while IFS= read -r app_path || [[ -n $app_path ]]; do
    [[ -n $app_path ]] || continue
    "$OPEN_COMMAND" -gj "$app_path" ||
      printf '[macos-cask-update] failed to reopen application: %s\n' "$app_path" >&2
  done <"$restart_file"
}

cleanup() {
  local status=$?
  trap - EXIT
  reopen_apps || true
  rm -rf "$temporary_directory"
  exit "$status"
}
```

Call `record_running_apps "$cask"` immediately after `is_outdated "$cask" || continue` and before prefetching. Keep Homebrew responsible for quitting applications; do not add `kill`, `pkill`, or `osascript` termination logic.

- [ ] **Step 4: Run focused and syntax tests and make them GREEN**

Run:

```bash
bats tests/bash/macos_homebrew_cask_update.bats
bash -n scripts/sh/update-homebrew-casks.sh
shellcheck scripts/sh/update-homebrew-casks.sh tests/bash/macos_homebrew_cask_update.bats
```

Expected: all restart, retry, error, and convergence cases pass with no lint findings.

- [ ] **Step 5: Perform the mutation check**

Temporarily change `"$OPEN_COMMAND" -gj "$app_path"` to `:` and rerun the Bats file. Expected: the two running-app tests fail. Revert the temporary mutation before continuing.

- [ ] **Step 6: Commit application lifecycle handling**

```bash
task commit DOTFILES_PATH="$PWD" -- "feat: restore apps after macOS cask updates"
```

---

### Task 3: Integrate the updater into `nrs` and split nix-darwin responsibilities

**Files:**

- Modify: `scripts/sh/install-macos.sh`
- Modify: `nix/darwin/default.nix`
- Modify: `tests/bash/install_macos.bats`
- Modify: `tests/bash/macos_config.bats`

**Interfaces:**

- Consumes: Task 2 executable updater.
- Produces: `DOTFILES_HOMEBREW_CASK_UPDATER` override and this runtime order: nix-darwin switch → cask updater → Docker runtime → chezmoi/Hermes verification.

- [ ] **Step 1: Write failing installer-order and failure-propagation tests**

In `tests/bash/install_macos.bats` setup, configure a fake updater.

```bash
export DOTFILES_HOMEBREW_CASK_UPDATER="$STUB_BIN/update-homebrew-casks"
export HOMEBREW_CASK_UPDATE_STATUS=0
write_stub update-homebrew-casks '
printf "update-homebrew-casks %s\n" "$*" >>"$COMMAND_LOG"
exit "$HOMEBREW_CASK_UPDATE_STATUS"
'
```

Extend the existing installed-prerequisites order assertion so the cask updater must run after nix-darwin and before Docker/chezmoi.

```bash
assert_log_order \
  "nix run .#darwin-rebuild -- switch --flake .#macos --impure" \
  "update-homebrew-casks " \
  "docker info" \
  "chezmoi init --source $REPO_ROOT/chezmoi"
```

Add the failure case.

```bash
@test "cask update failure stops macOS before Docker runtime and chezmoi" {
  write_installed_stubs
  export HOMEBREW_CASK_UPDATE_STATUS=47

  run "$INSTALLER"

  [ "$status" -eq 47 ]
  grep -q '^update-homebrew-casks ' "$COMMAND_LOG"
  ! grep -q '^chezmoi ' "$COMMAND_LOG"
  ! grep -q '^verify-environment ' "$COMMAND_LOG"
}
```

- [ ] **Step 2: Write failing evaluated nix-darwin contract test**

Replace the source-grep test named `Darwin activation updates cask metadata without forcing latest cask upgrades` in `tests/bash/macos_config.bats` with an evaluated contract.

```bash
@test "Darwin separates missing-cask installation from explicit greedy upgrades" {
  command -v nix >/dev/null 2>&1 || skip "nix is not available in this test environment"

  run env DOTFILES_USER=codex DOTFILES_HOME=/Users/codex \
    nix eval --impure --json --expr "
      let config = (builtins.getFlake (toString $REPO_ROOT)).darwinConfigurations.macos.config;
      in {
        inherit (config.homebrew) greedyCasks;
        inherit (config.homebrew.onActivation) autoUpdate upgrade;
      }
    "

  [ "$status" -eq 0 ]
  [ "$output" = '{"autoUpdate":true,"greedyCasks":true,"upgrade":false}' ]
}
```

- [ ] **Step 3: Run the integration tests and verify RED**

Run:

```bash
bats tests/bash/install_macos.bats tests/bash/macos_config.bats
```

Expected: FAIL because `install-macos.sh` does not invoke the updater and nix-darwin still evaluates to `greedyCasks = false`, `upgrade = true`.

- [ ] **Step 4: Integrate the updater after nix-darwin activation**

Add the command override next to the other `install-macos.sh` path settings.

```bash
HOMEBREW_CASK_UPDATER="${DOTFILES_HOMEBREW_CASK_UPDATER:-$ROOT/scripts/sh/update-homebrew-casks.sh}"
```

Add it to `preflight` required paths and call it in `main` at the approved boundary.

```bash
  apply_darwin_system
  "$HOMEBREW_CASK_UPDATER"
  setup_docker_runtime
```

Do not run the updater through `sudo`; Homebrew and application processes belong to `DOTFILES_USER`.

- [ ] **Step 5: Change nix-darwin's Homebrew contract**

Modify `nix/darwin/default.nix`:

```nix
    greedyCasks = true;
    onActivation = {
      autoUpdate = true;
      upgrade = false;
      cleanup = "none";
    };
```

Update the nearby comment to state that nix-darwin installs missing casks and `update-homebrew-casks.sh` performs explicit greedy upgrades with retries and verification.

- [ ] **Step 6: Run integration and focused updater tests and make them GREEN**

Run:

```bash
bats tests/bash/macos_homebrew_cask_update.bats tests/bash/install_macos.bats tests/bash/macos_config.bats
bash -n scripts/sh/install-macos.sh scripts/sh/update-homebrew-casks.sh
shellcheck scripts/sh/install-macos.sh scripts/sh/update-homebrew-casks.sh tests/bash/macos_homebrew_cask_update.bats
```

Expected: all tests and shell checks pass.

- [ ] **Step 7: Evaluate the generated activation command**

Run:

```bash
system_path="$(DOTFILES_USER=ktome1995 DOTFILES_HOME=/Users/ktome1995 nix build --impure --no-link --print-out-paths .#darwinConfigurations.macos.system)"
rg -n -C 2 'brew bundle' "$system_path/activate"
```

Expected: the generated Homebrew activation invokes `brew bundle --no-upgrade`; it must not perform the implicit upgrade pass.

- [ ] **Step 8: Commit `nrs` integration**

```bash
task commit DOTFILES_PATH="$PWD" -- "fix: converge macOS casks during nrs"
```

---

### Task 4: Document, run the complete regression suite, and perform the macOS smoke test

**Files:**

- Modify: `docs/nix/package-management.md`
- Modify: `docs/nix/homebrew-cask-troubleshooting.md`

**Interfaces:**

- Consumes: the integrated updater from Tasks 1–3.
- Produces: user-facing `nrs` behavior documentation and final verification evidence.

- [ ] **Step 1: Document the new update and failure semantics**

Add this behavior to the macOS section of `docs/nix/package-management.md`:

```markdown
`nrs` は nix-darwin で不足 cask を導入した後、宣言済み cask を `--greedy` で更新します。各 download/upgrade は最大3回再試行され、更新前に起動していたアプリは更新後に再起動されます。未更新の cask が残る場合、`nrs` は非ゼロで終了します。
```

Add recovery guidance to `docs/nix/homebrew-cask-troubleshooting.md`:

```markdown
`Fetching ...` で失敗した場合は `~/Library/Caches/Homebrew/downloads/*.incomplete` を手動削除せず、そのまま `nrs` を再実行します。専用 updater が Homebrew の cache を使って最大3回再試行し、最後に宣言済み cask の収束を検証します。
```

- [ ] **Step 2: Run the full automated validation**

Run:

```bash
task test:bash DOTFILES_PATH="$PWD"
pre-commit run --all-files
git diff --check
```

Expected: all 150 existing Bats tests plus the new tests pass, all pre-commit hooks pass, and `git diff --check` emits no output.

- [ ] **Step 3: Review the complete diff against the design**

Run:

```bash
git diff main...HEAD --stat
git diff main...HEAD -- \
  nix/darwin/default.nix \
  scripts/sh/install-macos.sh \
  scripts/sh/update-homebrew-casks.sh \
  tests/bash/install_macos.bats \
  tests/bash/macos_config.bats \
  tests/bash/macos_homebrew_cask_update.bats \
  docs/nix/package-management.md \
  docs/nix/homebrew-cask-troubleshooting.md
```

Expected: no unrelated changes; every design success criterion maps to code or a behavioral test.

- [ ] **Step 4: Commit documentation**

```bash
task commit DOTFILES_PATH="$PWD" -- "docs: explain macOS cask convergence"
```

- [ ] **Step 5: Run the real macOS smoke test only after warning about app termination**

Because this step updates and quits GUI applications, first notify the user that Claude, Docker Desktop, Orca, Chrome, VS Code, or other declared casks may close and reopen. Then run from a terminal that is not hosted by an application being upgraded:

```bash
./install.sh
HOMEBREW_NO_AUTO_UPDATE=1 /opt/homebrew/bin/brew outdated --cask --greedy \
  1password claude thebrowsercompany-dia docker-desktop google-chrome \
  stablyai/orca/orca raycast tableplus visual-studio-code
```

Expected: `./install.sh` completes through `[macos-install] macOS setup complete.` and the final `brew outdated` command prints nothing. `wezterm@nightly` is intentionally absent from this command because its dedicated archive installer owns it.

- [ ] **Step 6: Record final workspace state**

Run:

```bash
git status --short --branch
git log --oneline main..HEAD
```

Expected: clean worktree with the design, updater, lifecycle, integration, and documentation commits present.
