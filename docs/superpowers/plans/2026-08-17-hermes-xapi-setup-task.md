# Hermes X API Setup Task Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one memorable `hermes:xapi:setup` task that executes OAuth authentication, refresh-token synchronization, and xapi-mcp restart in order without duplicating the existing `nrs` bootstrap path.

**Architecture:** Keep `hermes:xapi:auth`, `hermes:xapi:sync-token`, and `hermes:xapi:restart` as atomic public tasks. Add a readable Taskfile composite task that invokes those tasks sequentially. Keep `nrs` routed through the existing `hermes:bootstrap` task because that adapter already performs the non-interactive 1Password-backed xapi startup.

**Tech Stack:** go-task Taskfile v3, Bash, PowerShell, Bats, Python unittest, Markdown.

## Global Constraints

- Preserve existing public task names and existing dirty changes.
- Do not add an interactive OAuth step to `nrs` or `hermes:bootstrap`.
- Do not pass or print OAuth secrets in Taskfile commands or documentation.
- Reuse existing atomic tasks; do not duplicate their adapter commands.
- The composite task must stop before restart if authentication or token synchronization fails.

---

### Task 1: Add failing Taskfile contract coverage

**Files:**

- Modify: `tests/bash/taskfile_test_routing.bats:35-58`

**Interfaces:**

- Consumes: existing root Taskfile include layout and public `hermes:xapi:*` tasks.
- Produces: a regression test that requires `hermes:xapi:setup` and its exact dry-run order.

- [ ] **Step 1: Write the failing test**

Add a Bats test after the existing token-sync test:

```bash
@test "xapi setup runs auth, token sync, and restart in order" {
  command -v task >/dev/null || skip "go-task is unavailable"

  run task --dir "$REPO_ROOT" --dry hermes:xapi:setup

  [ "$status" -eq 0 ]
  auth_line="$(grep -n 'task: \[hermes:xapi:auth\]' <<<"$output" | cut -d: -f1)"
  sync_line="$(grep -n 'task: \[hermes:xapi:sync-token\]' <<<"$output" | cut -d: -f1)"
  restart_line="$(grep -n 'task: \[hermes:xapi:restart\]' <<<"$output" | cut -d: -f1)"
  [ -n "$auth_line" ]
  [ -n "$sync_line" ]
  [ -n "$restart_line" ]
  [ "$auth_line" -lt "$sync_line" ]
  [ "$sync_line" -lt "$restart_line" ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
bats tests/bash/taskfile_test_routing.bats -f "xapi setup runs auth"
```

Expected: FAIL because `hermes:xapi:setup` does not exist.

### Task 2: Add the readable composite Taskfile task

**Files:**

- Modify: `taskfiles/hermes/taskfile.yml:90`
- Modify: `tests/bash/taskfile_test_routing.bats:26-32`

**Interfaces:**

- Consumes: `hermes:xapi:auth`, `hermes:xapi:sync-token`, and `hermes:xapi:restart`.
- Produces: public interactive task `hermes:xapi:setup`.

- [ ] **Step 1: Add the composite task**

Insert this task before `hermes:xapi:sync-token`:

```yaml
hermes:xapi:setup:
  desc: Authenticate, sync the X API refresh token, and restart the MCP bridge
  interactive: true
  preconditions:
    - sh: docker info
      msg: "Docker daemon is not running. Start Docker Desktop and try again."
    - sh: test -f {{.HERMES_COMPOSE_FILE}}
      msg: "Hermes compose file not found: {{.HERMES_COMPOSE_FILE}}"
  cmds:
    - task: hermes:xapi:auth
    - task: hermes:xapi:sync-token
    - task: hermes:xapi:restart
```

- [ ] **Step 2: Extend the task listing contract**

In the existing task-list test, assert that `hermes:xapi:setup` appears in
`task --list` output immediately beside the existing xapi tasks.

- [ ] **Step 3: Run the focused tests**

Run:

```bash
bats tests/bash/taskfile_test_routing.bats -f "xapi"
```

Expected: PASS for the new setup test, token-sync test, and task-list coverage.

### Task 3: Update user-facing setup documentation

**Files:**

- Modify: `docs/hermes-agent/xapi-mcp.md:54-112`
- Modify: `docs/chezmoi/secrets.md:117-120`
- Modify: `scripts/sh/hermes-xapi.sh:81-83`

**Interfaces:**

- Consumes: the new `hermes:xapi:setup` public task.
- Produces: one remembered first-time/re-authentication command while retaining the atomic auth recovery command.

- [ ] **Step 1: Update the first-authentication command**

Change the primary documented command to:

```bash
task hermes:xapi:setup
```

Explain that it performs `auth`, `sync-token`, and `restart` in that order.
Retain `task hermes:xapi:auth` only as the explicit OAuth-only recovery command.

- [ ] **Step 2: Preserve the headless callback explanation**

Document that an unreachable `localhost:8080` page after X approval is expected;
the complete callback URL or requested code must be pasted into the waiting
terminal. Do not instruct users to expose the internal MCP port.

- [ ] **Step 3: Update the secrets overview**

Replace the list of normal explicit commands so it names `task hermes:xapi:setup`
as the standard first-time flow and keeps `auth` as the OAuth-only recovery path.

- [ ] **Step 4: Update the Bash adapter usage text**

Include `sync-token` in the adapter's usage message so the existing internal
command surface is accurate.

- [ ] **Step 5: Run documentation and syntax checks**

Run:

```bash
bash -n scripts/sh/hermes-xapi.sh
git diff --check
```

Expected: both commands exit successfully.

### Task 4: Run the complete relevant verification suite

**Files:**

- Test: `tests/bash/taskfile_test_routing.bats`
- Test: `tests/bash/hermes_agent.bats`
- Test: `tests/python/test_taskfile_contract.py`
- Test: `scripts/powershell/tests/lib/HermesXApi.Tests.ps1`

**Interfaces:**

- Consumes: all implementation and documentation changes from Tasks 1–3.
- Produces: fresh evidence that Unix, Windows adapter contracts, and Taskfile routing remain valid.

- [ ] **Step 1: Run Bash tests**

```bash
bats tests/bash/taskfile_test_routing.bats tests/bash/hermes_agent.bats
```

- [ ] **Step 2: Run Python Taskfile contracts**

```bash
python3 -m unittest tests/python/test_taskfile_contract.py
```

- [ ] **Step 3: Run PowerShell adapter tests when available**

```bash
pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1 -Path scripts/powershell/tests/lib/HermesXApi.Tests.ps1
```

If `pwsh` is unavailable, report that test as unrun rather than claiming full
cross-platform verification.

- [ ] **Step 4: Inspect the final scoped diff**

```bash
git diff --check
git diff -- taskfiles/hermes/taskfile.yml tests/bash/taskfile_test_routing.bats docs/hermes-agent/xapi-mcp.md docs/chezmoi/secrets.md scripts/sh/hermes-xapi.sh
```

Confirm that no unrelated dirty files were staged or modified by this change.
