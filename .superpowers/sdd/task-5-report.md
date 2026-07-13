# Task 5 verification report

Status: BLOCKED / NEEDS_FIX

Reason: verification stopped during Step 1 because the `[o]penclaw` grep check returned matches, while the Task 5 brief expected no `[o]penclaw` matches. No code changes were made.

## Context

- Repository: `D:\ruru\dotfiles`
- Branch: `codex/hermes-browser-mcp-container`
- HEAD: `7514cfe`
- Note: The requested Docker `down` step was not reached. Therefore the existing Hermes compose project/container was not stopped by this verification run.

## Commands executed

### Pre-check: current git state

Command:

```powershell
git status --short --branch
```

Exit status: 0

Key output:

```text
## codex/hermes-browser-mcp-container...origin/main [ahead 11]
```

Command:

```powershell
git rev-parse --short HEAD
git branch --show-current
```

Exit status: 0

Key output:

```text
7514cfe
codex/hermes-browser-mcp-container
```

### Step 1: static checks

Command:

```powershell
git diff --check
```

Exit status: 0

Key output: no output.

Command:

```powershell
git grep -n -i [o]penclaw -- ':!*.lock'
```

Exit status: 0

Key output:

```text
docs/superpowers/plans/2026-07-13-hermes-browser-mcp-container-plan.md:257:git grep -n -i [o]penclaw -- ':!*.lock'
docs/superpowers/plans/2026-07-13-hermes-browser-mcp-container-plan.md:262:Expected: no [o]penclaw matches, no diff errors, and all selected tests pass.
```

Interpretation: the command successfully found two case-insensitive `[o]penclaw` matches. These are in a planning document, not implementation code, but they still violate the Task 5 expected result: "no [o]penclaw matches".

## Commands not executed

The following Task 5 commands were not executed because verification stopped at the first concrete expectation failure:

- focused `Handler.HermesAgent` Pester
- focused `ChezmoiTemplate` Pester
- `docker compose -f docker/hermes-agent/compose.yml build chromium browser-mcp`
- `docker compose -f docker/hermes-agent/compose.yml up -d chromium browser-mcp`
- `docker compose -f docker/hermes-agent/compose.yml ps`
- internal CDP reachability checks from `chromium` and `browser-mcp`
- Hermes startup, log inspection, config inspection, and MCP endpoint/tool-list handshake
- profile persistence `down` / `up` check
- final `git status --short --branch`
- final `git diff --check`
- full repository `task test`

## Test counts

- Pester focused tests: not run.
- Full repository test task: not run.
- Docker smoke tests: not run.

## Limitations

- Because Step 1 failed, no Docker services were started or stopped by this run.
- The pre-existing Hermes compose project/container remains untouched by this verification run.
- MCP endpoint/tool-list handshake was not attempted.

## Suggested next action

Decide whether the `[o]penclaw` grep check should exclude historical planning documents such as `docs/superpowers/plans/*.md`, or whether those plan references should be removed/renamed. After that decision, rerun Task 5 from Step 1.

## Re-run after 6e5b8a4 grep fix - 2026-07-13 23:31:32 +09:00

Status: NEEDS_FIX / BLOCKED.

Verification was re-run on branch `codex/hermes-browser-mcp-container` at commit `6e5b8a4`. No code changes were made. Verification exposed a new concrete runtime defect in the Chromium container startup path, so the remaining Docker/Hermes/MCP/profile/full-test steps were not executed.

### Initial state

Command:

```powershell
git status --short --branch
```

Exit status: 0

Key output:

```text
## codex/hermes-browser-mcp-container...origin/main [ahead 12]
```

Command:

```powershell
git log --oneline -5
```

Exit status: 0

Key output:

```text
6e5b8a4 'fix browser verification grep'
7514cfe 'configure Hermes browser MCP'
933da93 'wire Hermes browser services'
3054a6d 'fix Browser MCP TCP healthcheck'
9dc4668 'add isolated Chrome DevTools MCP container'
```

### Step 1: static checks and focused tests

Command:

```powershell
git diff --check
```

Exit status: 0

Key output: no output.

Command:

```powershell
git grep -n -i [o]penclaw -- ':!*.lock'
```

Exit status: 1

Key output: no output.

Interpretation: `git grep` exit 1 means no matches, which satisfies the Task 5 expectation of no [o]penclaw matches.

Command:

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path './scripts/powershell/tests/handlers/Handler.HermesAgent.Tests.ps1' -Output Normal"
```

Exit status: 0

Key output:

```text
Discovery found 53 tests in 235ms.
Tests completed in 18.46s
Tests Passed: 53, Failed: 0, Skipped: 0, Inconclusive: 0, NotRun: 0
```

Command:

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path './scripts/powershell/tests/chezmoi/ChezmoiTemplate.Tests.ps1' -Output Normal"
```

Exit status: 0

Key output:

```text
Discovery found 42 tests in 809ms.
Tests completed in 3.93s
Tests Passed: 42, Failed: 0, Skipped: 0, Inconclusive: 0, NotRun: 0
```

### Step 2: build and start isolated browser services

Command:

```powershell
docker compose -f docker/hermes-agent/compose.yml build chromium browser-mcp
```

Exit status: 0

Key output:

```text
Image local/hermes-browser-mcp:latest Built
Image local/hermes-browser:latest Built
```

Command:

```powershell
docker compose -f docker/hermes-agent/compose.yml up -d chromium browser-mcp
```

Exit status: 1

Key output:

```text
Network hermes-browser Creating
Network hermes-browser Created
Container hermes-chromium Creating
Container hermes-chromium Created
Container hermes-browser-mcp Creating
Container hermes-browser-mcp Created
Container hermes-chromium Starting
Container hermes-chromium Started
Container hermes-chromium Waiting
Container hermes-chromium Error dependency chromium failed to start
dependency failed to start: container hermes-chromium is unhealthy
```

Command:

```powershell
docker compose -f docker/hermes-agent/compose.yml ps
```

Exit status: 0

Key output:

```text
NAME              IMAGE                          COMMAND                  SERVICE    CREATED          STATUS                                     PORTS
hermes            local/hermes-agent-gh:latest   "/init /opt/hermes/d…"   hermes     7 days ago       Up 5 days                                  127.0.0.1:8642->8642/tcp, 127.0.0.1:9119->9119/tcp
hermes-chromium   local/hermes-browser:latest    "/usr/local/bin/entr…"   chromium   15 seconds ago   Up Less than a second (health: starting)
```

Interpretation: an existing `hermes` compose container was already running from a previous run. The Task 5 `docker compose ... down` step was not reached, so this run did not stop the existing Hermes compose project.

Command:

```powershell
docker compose -f docker/hermes-agent/compose.yml logs --no-color --tail=120 chromium
```

Exit status: 0

Key output:

```text
hermes-chromium | No usable sandbox! If this is a Debian system, please install the chromium-sandbox package to solve this problem. ... If you want to live dangerously and need an immediate workaround, you can try using --no-sandbox.
```

The same Chromium sandbox error repeated across restart attempts.

Command:

```powershell
docker inspect --format '{{json .State.Health}}' hermes-chromium
```

Exit status: 0

Key output:

```json
{ "Status": "unhealthy", "FailingStreak": 0, "Log": [] }
```

Relevant static evidence:

```text
docker/hermes-browser/Dockerfile installs chromium curl ca-certificates, but not chromium-sandbox.
docker/hermes-browser/entrypoint.sh starts /usr/bin/chromium without --no-sandbox.
```

### Commands not executed after the defect

The following Task 5 commands were not executed because `docker compose up -d chromium browser-mcp` failed before Browser MCP could start:

- `docker compose -f docker/hermes-agent/compose.yml ps` healthy/no-host-port acceptance check beyond the failure snapshot above
- internal CDP reachability from `chromium`
- internal CDP reachability from `browser-mcp`
- `docker compose -f docker/hermes-agent/compose.yml up -d hermes`
- Hermes log inspection for the new startup path
- root/profile config verification for internal browser URL
- MCP endpoint/tool-list handshake
- profile persistence `docker compose ... down` / `up` check
- final full `task test`

### Test counts

- Handler.HermesAgent focused Pester: 53 passed, 0 failed.
- ChezmoiTemplate focused Pester: 42 passed, 0 failed.
- Full repository `task test`: not run because Docker smoke verification exposed a blocking container startup defect first.
- Docker smoke: build passed; Chromium startup failed before CDP/MCP/Hermes smoke tests.

### Limitation and next action

The MCP endpoint/tool-list handshake was not attempted because Browser MCP depends on Chromium becoming healthy, and Chromium never reached a healthy state.

Concrete defect to fix before rerunning Task 5: the Debian Chromium container cannot start with the current sandbox configuration. The runtime error recommends installing `chromium-sandbox` or using `--no-sandbox`; the Dockerfile currently does not install `chromium-sandbox`, and the entrypoint intentionally starts Chromium without `--no-sandbox`.

## Fix applied - 2026-07-13 23:40:07 +09:00

Root cause: the Debian Chromium image installed `chromium` without the `chromium-sandbox` package, so Chromium refused to start with `No usable sandbox!`. The design forbids `--no-sandbox`, so the fix is to provide the Debian sandbox helper package.

Fix:

- Updated `docker/hermes-browser/Dockerfile` to install `chromium-sandbox` alongside `chromium`, while preserving `--no-install-recommends`, apt cleanup, and the non-root `hermes-browser` runtime user.
- Strengthened `scripts/powershell/tests/handlers/Handler.HermesAgent.Tests.ps1` so the Chromium image contract requires `chromium-sandbox` and still rejects `--no-sandbox` across the Dockerfile/entrypoint contract.

Verification:

- RED: focused Pester failed before the Dockerfile fix with 52 passed, 1 failed because `chromium-sandbox` was absent.
- GREEN: `pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path './scripts/powershell/tests/handlers/Handler.HermesAgent.Tests.ps1' -Output Detailed"` exited 0 with 53 passed, 0 failed.
- Build: `docker compose -f docker/hermes-agent/compose.yml build chromium` exited 0 and built `local/hermes-browser:latest`.

Not run: the full Task 5 runtime sequence, by request.

## Re-run verification after Chromium sandbox package fix - 2026-07-13 23:49:11 +09:00

Scope:

- Branch: `codex/hermes-browser-mcp-container`
- HEAD: `3476096 install Chromium sandbox package`
- This run did not make code changes.
- An existing `hermes` compose service was already running before this run: `hermes    local/hermes-agent-gh:latest ... Up 5 days ... 127.0.0.1:8642->8642/tcp, 127.0.0.1:9119->9119/tcp`.
- The brief's `docker compose ... down` step was not reached, so this run did not stop the existing Hermes compose project. After the Chromium failure, only `chromium` and `browser-mcp` were stopped with `docker compose ... stop chromium browser-mcp`.

### Step 1: static checks and focused tests

Command:

```powershell
git diff --check
```

Exit status: 0

Key output: no output.

Command:

```powershell
git grep -n -i [o]penclaw -- ':!*.lock'
```

Exit status: 1

Key output: no output.

Interpretation: `git grep` exit 1 means no matches, satisfying the Task 5 expectation of no [o]penclaw matches.

Command:

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path './scripts/powershell/tests/handlers/Handler.HermesAgent.Tests.ps1' -Output Normal"
```

Exit status: 0

Key output:

```text
Discovery found 53 tests in 1.02s.
Tests completed in 22.15s
Tests Passed: 53, Failed: 0, Skipped: 0, Inconclusive: 0, NotRun: 0
```

Command:

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path './scripts/powershell/tests/chezmoi/ChezmoiTemplate.Tests.ps1' -Output Normal"
```

Exit status: 0

Key output:

```text
Discovery found 42 tests in 1.79s.
Tests completed in 8.3s
Tests Passed: 42, Failed: 0, Skipped: 0, Inconclusive: 0, NotRun: 0
```

### Step 2: build and start isolated browser services

Command:

```powershell
docker compose -f docker/hermes-agent/compose.yml build chromium browser-mcp
```

Exit status: 0

Key output:

```text
Image local/hermes-browser:latest Built
Image local/hermes-browser-mcp:latest Built
```

Build detail confirmed `chromium-sandbox` is now in the cached Chromium image install step:

```text
RUN apt-get update && apt-get install -y --no-install-recommends chromium chromium-sandbox curl ca-certificates ...
```

Command:

```powershell
docker compose -f docker/hermes-agent/compose.yml up -d chromium browser-mcp
```

Exit status: 1

Key output:

```text
Container hermes-chromium Starting
Container hermes-chromium Started
Container hermes-chromium Waiting
Container hermes-chromium Error dependency chromium failed to start
dependency failed to start: container hermes-chromium is unhealthy
```

Command:

```powershell
docker compose -f docker/hermes-agent/compose.yml ps
```

Exit status: 0

Key output:

```text
NAME              IMAGE                          COMMAND                  SERVICE    CREATED          STATUS                                    PORTS
hermes            local/hermes-agent-gh:latest   "/init /opt/hermes/d…"   hermes     7 days ago       Up 5 days                                 127.0.0.1:8642->8642/tcp, 127.0.0.1:9119->9119/tcp
hermes-chromium   local/hermes-browser:latest    "/usr/local/bin/entr…"   chromium   17 seconds ago   Restarting (139) Less than a second ago
```

The `chromium` service did not publish host ports 9222 or 8080. Browser MCP did not reach a running state because it depends on healthy Chromium.

Command:

```powershell
docker compose -f docker/hermes-agent/compose.yml logs --no-color --tail=160 chromium
```

Exit status: 0

Key output:

```text
hermes-chromium | Failed to move to new namespace: PID namespaces supported, Network namespace supported, but failed: errno = Operation not permitted
hermes-chromium | [1:1:0713/144836.685395:FATAL:content/browser/zygote_host/zygote_host_impl_linux.cc:207] Check failed: . : Operation not permitted (1)
```

The same namespace/zygote fatal error repeated across restart attempts. This is different from the previous `No usable sandbox! ... install the chromium-sandbox package` failure.

Command:

```powershell
docker inspect --format '{{json .State.Health}}' hermes-chromium
```

Exit status: 0

Key output:

```json
{ "Status": "unhealthy", "FailingStreak": 0, "Log": [] }
```

Command:

```powershell
docker compose -f docker/hermes-agent/compose.yml logs --no-color --tail=80 browser-mcp
```

Exit status: 0

Key output: no output.

Command:

```powershell
docker compose -f docker/hermes-agent/compose.yml stop chromium browser-mcp
```

Exit status: 0

Key output:

```text
Container hermes-browser-mcp Stopping
Container hermes-browser-mcp Stopped
Container hermes-chromium Stopping
Container hermes-chromium Stopped
```

### Commands not executed after the defect

The following Task 5 commands were not executed because `docker compose up -d chromium browser-mcp` failed before Browser MCP could start:

- full healthy/no-host-port acceptance check beyond the failure snapshot above
- internal CDP reachability from `chromium`
- internal CDP reachability from `browser-mcp`
- `docker compose -f docker/hermes-agent/compose.yml up -d hermes`
- Hermes log inspection for the new startup path
- root/profile config verification for internal browser URL
- MCP endpoint/tool-list handshake
- profile persistence `docker compose ... down` / `up` check
- full repository `task test`

### Final checks after stopping failed services

Command:

```powershell
git status --short --branch
```

Exit status: 0

Key output:

```text
## codex/hermes-browser-mcp-container...origin/main [ahead 13]
```

Command:

```powershell
git diff --check
```

Exit status: 0

Key output: no output.

### Test counts

- Handler.HermesAgent focused Pester: 53 passed, 0 failed.
- ChezmoiTemplate focused Pester: 42 passed, 0 failed.
- Docker build: passed for `chromium` and `browser-mcp`.
- Docker smoke: failed at `docker compose up -d chromium browser-mcp`; Chromium restarted with exit 139 and became unhealthy.
- Full repository `task test`: not run because Docker smoke verification exposed a blocking container startup defect first.

### Limitation and next action

The MCP endpoint/tool-list handshake was not attempted because Browser MCP depends on Chromium becoming healthy, and Chromium never reached a healthy state.

Concrete defect to fix before rerunning Task 5: after installing `chromium-sandbox`, Chromium now starts far enough to attempt sandbox namespace setup, but the container runtime denies namespace creation with `Operation not permitted`, causing the Chromium process to crash in `zygote_host_impl_linux.cc:207` and the Compose health dependency to fail.

## Fix applied for Chromium sandbox namespace - 2026-07-13

Root cause: after `chromium-sandbox` was installed, Chromium reached Linux sandbox namespace setup, but Docker's default runtime capability set denied the namespace operation with `Operation not permitted`. The failure was in Chromium's zygote sandbox path, not in the image package set.

Chosen permission: add `cap_add: [SYS_ADMIN]` to the `chromium` Compose service only. This keeps Chromium sandbox enabled and avoids the forbidden `--no-sandbox` workaround.

Commands and results:

- RED focused Pester before Compose fix: `Handler.HermesAgent.Tests.ps1` reported 52 passed, 1 failed because `chromium` lacked `cap_add: - SYS_ADMIN`.
- GREEN focused Pester after Compose fix: `pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path './scripts/powershell/tests/handlers/Handler.HermesAgent.Tests.ps1' -Output Detailed"` reported 53 passed, 0 failed.
- Build: `docker compose -f docker/hermes-agent/compose.yml build chromium` exited 0 and built `local/hermes-browser:latest`.
- Runtime: `docker compose -f docker/hermes-agent/compose.yml up -d chromium` exited 0 and recreated/started `hermes-chromium`.
- Health: `docker compose -f docker/hermes-agent/compose.yml ps chromium` showed `hermes-chromium` as `Up ... (healthy)` with no host ports listed.
- CDP smoke: `docker compose -f docker/hermes-agent/compose.yml exec -T chromium curl -fsS http://127.0.0.1:9222/json/version` exited 0 and returned Chrome/150 `/json/version` metadata.
- Cleanup: `docker compose -f docker/hermes-agent/compose.yml stop chromium` stopped `hermes-chromium`, because Chromium was not running before this smoke test.

Security note: this does not add `privileged: true`, does not publish Chromium CDP port 9222 or Browser MCP port 8080 to the host, and does not add `--no-sandbox`. The added runtime capability is scoped to the internal `chromium` service.

## Full Task 5 verification rerun after fixes 3476096 and 75b0d21 - 2026-07-14

Branch: `codex/hermes-browser-mcp-container`

Scope: reran Task 5 verification commands as written where feasible. No code changes were made. Verification stopped after a concrete Docker runtime defect reproduced.

### Step 1: repository static checks

Command:

```powershell
git diff --check
```

Exit status: 0

Key output: no output.

Command:

```powershell
git grep -n -i [o]penclaw -- ':!*.lock'
```

Exit status: 1

Key output: no output. This is the expected "no matches" result.

Command:

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path './scripts/powershell/tests/handlers/Handler.HermesAgent.Tests.ps1' -Output Normal"
```

Exit status: 0

Key output:

```text
Discovery found 53 tests in 356ms.
Tests completed in 18.53s
Tests Passed: 53, Failed: 0, Skipped: 0, Inconclusive: 0, NotRun: 0
```

Command:

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path './scripts/powershell/tests/chezmoi/ChezmoiTemplate.Tests.ps1' -Output Normal"
```

Exit status: 0

Key output:

```text
Discovery found 42 tests in 252ms.
Tests completed in 1.54s
Tests Passed: 42, Failed: 0, Skipped: 0, Inconclusive: 0, NotRun: 0
```

### Step 2: build and start isolated browser services

Command:

```powershell
docker compose -f docker/hermes-agent/compose.yml build chromium browser-mcp
```

Exit status: 0

Key output:

```text
Image local/hermes-browser:latest Built
Image local/hermes-browser-mcp:latest Built
```

Command:

```powershell
docker compose -f docker/hermes-agent/compose.yml up -d chromium browser-mcp
```

Exit status: 1

Key output:

```text
Container hermes-chromium Recreate
Container hermes-chromium Recreated
Container hermes-browser-mcp Recreate
Container hermes-browser-mcp Recreated
Container hermes-chromium Starting
Container hermes-chromium Started
Container hermes-chromium Waiting
Container hermes-chromium Error dependency chromium failed to start
dependency failed to start: container hermes-chromium is unhealthy
```

Command:

```powershell
docker compose -f docker/hermes-agent/compose.yml ps
```

Exit status: 0

Key output:

```text
NAME              IMAGE                          COMMAND                  SERVICE    CREATED          STATUS                          PORTS
hermes            local/hermes-agent-gh:latest   "/init /opt/hermes/d…"   hermes     7 days ago       Up 5 days                       127.0.0.1:8642->8642/tcp, 127.0.0.1:9119->9119/tcp
hermes-chromium   local/hermes-browser:latest    "/usr/local/bin/entr…"   chromium   18 seconds ago   Restarting (21) 2 seconds ago
```

No host port was listed for Chromium 9222 or Browser MCP 8080. The already-running `hermes` service had its own host ports 8642 and 9119 from the existing compose project.

Command:

```powershell
docker inspect --format '{{json .State}}' hermes-chromium
```

Exit status: 0

Key output:

```json
{
  "Status": "restarting",
  "Running": true,
  "Paused": false,
  "Restarting": true,
  "OOMKilled": false,
  "Dead": false,
  "Pid": 0,
  "ExitCode": 21,
  "Error": "",
  "StartedAt": "2026-07-13T15:04:53.546820056Z",
  "FinishedAt": "2026-07-13T15:04:53.835149033Z",
  "Health": { "Status": "unhealthy", "FailingStreak": 0, "Log": [] }
}
```

Command:

```powershell
docker compose -f docker/hermes-agent/compose.yml logs --no-color --tail=120 chromium
```

Exit status: 0

Key output:

```text
hermes-chromium  | [1:1:0713/150439.080228:ERROR:chrome/browser/process_singleton_posix.cc:365] The profile appears to be in use by another Chromium process (1) on another computer (99ac7f6ebf7c). Chromium has locked the profile so that it doesn't get corrupted. If you are sure no other processes are using this profile, you can unlock the profile and relaunch Chromium.
hermes-chromium  | [1:1:0713/150439.080341:ERROR:chrome/browser/ui/views/message_box_dialog.cc:200] Unable to show message box: Chromium - The profile appears to be in use by another Chromium process (1) on another computer (99ac7f6ebf7c). Chromium has locked the profile so that it doesn't get corrupted. If you are sure no other processes are using this profile, you can unlock the profile and relaunch Chromium.
```

The same profile-lock error repeated across restart attempts.

Command:

```powershell
docker compose -f docker/hermes-agent/compose.yml logs --no-color --tail=80 browser-mcp
```

Exit status: 0

Key output: no output.

### Existing compose project cleanup and clean retry

Because the brief warned that an existing Hermes compose project/container may exist and Task 5 includes a `docker compose ... down` step, I ran the cleanup explicitly. This stopped and removed the existing Hermes compose project, including the `hermes` container that had been up for 5 days.

Command:

```powershell
docker ps -a --filter "name=hermes" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
```

Exit status: 0

Key output:

```text
NAMES                IMAGE                             STATUS                           PORTS
hermes-browser-mcp   local/hermes-browser-mcp:latest   Created
hermes-chromium      local/hermes-browser:latest       Restarting (21) 15 seconds ago
hermes               local/hermes-agent-gh:latest      Up 5 days                        127.0.0.1:8642->8642/tcp, 127.0.0.1:9119->9119/tcp
```

Command:

```powershell
docker compose -f docker/hermes-agent/compose.yml down
```

Exit status: 0

Key output:

```text
Container hermes Stopping
Container hermes Stopped
Container hermes Removing
Container hermes Removed
Container hermes-browser-mcp Stopping
Container hermes-browser-mcp Stopped
Container hermes-browser-mcp Removing
Container hermes-browser-mcp Removed
Container hermes-chromium Stopping
Container hermes-chromium Stopped
Container hermes-chromium Removing
Container hermes-chromium Removed
Network hermes-browser Removing
Network hermes-browser Removed
```

Command:

```powershell
docker compose -f docker/hermes-agent/compose.yml up -d chromium browser-mcp
```

Exit status: 1

Key output:

```text
Network hermes-browser Creating
Network hermes-browser Created
Container hermes-chromium Creating
Container hermes-chromium Created
Container hermes-browser-mcp Creating
Container hermes-browser-mcp Created
Container hermes-chromium Starting
Container hermes-chromium Started
Container hermes-chromium Waiting
Container hermes-chromium Error dependency chromium failed to start
dependency failed to start: container hermes-chromium is unhealthy
```

Command:

```powershell
docker compose -f docker/hermes-agent/compose.yml ps
```

Exit status: 0

Key output:

```text
NAME              IMAGE                         COMMAND                  SERVICE    CREATED          STATUS                         PORTS
hermes-chromium   local/hermes-browser:latest   "/usr/local/bin/entr…"   chromium   17 seconds ago   Restarting (21) 1 second ago
```

Command:

```powershell
docker inspect --format '{{json .State}}' hermes-chromium
```

Exit status: 0

Key output:

```json
{
  "Status": "restarting",
  "Running": true,
  "Paused": false,
  "Restarting": true,
  "OOMKilled": false,
  "Dead": false,
  "Pid": 0,
  "ExitCode": 21,
  "Error": "",
  "StartedAt": "2026-07-13T15:06:14.819206506Z",
  "FinishedAt": "2026-07-13T15:06:15.139394462Z",
  "Health": { "Status": "unhealthy", "FailingStreak": 0, "Log": [] }
}
```

Command:

```powershell
docker compose -f docker/hermes-agent/compose.yml logs --no-color --tail=80 chromium
```

Exit status: 0

Key output:

```text
hermes-chromium  | [1:1:0713/150559.922250:ERROR:chrome/browser/process_singleton_posix.cc:365] The profile appears to be in use by another Chromium process (1) on another computer (99ac7f6ebf7c). Chromium has locked the profile so that it doesn't get corrupted. If you are sure no other processes are using this profile, you can unlock the profile and relaunch Chromium.
hermes-chromium  | [1:1:0713/150559.922345:ERROR:chrome/browser/ui/views/message_box_dialog.cc:200] Unable to show message box: Chromium - The profile appears to be in use by another Chromium process (1) on another computer (99ac7f6ebf7c). Chromium has locked the profile so that it doesn't get corrupted. If you are sure no other processes are using this profile, you can unlock the profile and relaunch Chromium.
```

The clean retry reproduced the same profile-lock failure. Chromium still did not become healthy, and Browser MCP did not start.

Cleanup command:

```powershell
docker compose -f docker/hermes-agent/compose.yml stop chromium browser-mcp
```

Exit status: 0

Key output:

```text
Container hermes-browser-mcp Stopping
Container hermes-browser-mcp Stopped
Container hermes-chromium Stopping
Container hermes-chromium Stopped
```

### Commands not executed after the defect

The following commands/checks were not executed because `docker compose up -d chromium browser-mcp` failed before Chromium became healthy and before Browser MCP could start:

- internal CDP reachability from `chromium`
- internal CDP reachability from `browser-mcp`
- `docker compose -f docker/hermes-agent/compose.yml up -d hermes`
- Hermes log inspection for the new startup path
- root/profile config verification for the internal browser URL
- MCP endpoint/tool-list handshake
- profile persistence down/up acceptance check beyond the clean retry above
- full repository `task test`

### Final checks after stopping failed services

Command:

```powershell
git status --short --branch
```

Exit status: 0

Key output:

```text
## codex/hermes-browser-mcp-container...origin/main [ahead 14]
```

Command:

```powershell
git diff --check
```

Exit status: 0

Key output: no output.

### Test counts

- Handler.HermesAgent focused Pester: 53 passed, 0 failed.
- ChezmoiTemplate focused Pester: 42 passed, 0 failed.
- Docker build: passed for `chromium` and `browser-mcp`.
- Docker smoke: failed at `docker compose up -d chromium browser-mcp`; Chromium restarted with exit code 21 and became unhealthy.
- Full repository `task test`: not run because Docker smoke verification exposed a blocking runtime defect first.

### Result

Status: NEEDS_FIX / BLOCKED.

Concrete defect: after the namespace/capability fixes, Chromium now fails earlier Task 5 smoke startup because the persisted browser profile is locked by another Chromium process marker. The failure reproduces even after `docker compose -f docker/hermes-agent/compose.yml down` stops/removes the existing Hermes compose project and a clean `up -d chromium browser-mcp` is attempted. This prevents internal CDP verification, Browser MCP startup, Hermes startup, the MCP tool-list handshake, profile persistence verification, and full `task test`.

## Fix applied for stale Chromium profile singleton markers - 2026-07-14

Root cause: Chromium persisted stale process singleton markers in the dedicated browser profile bind mount after a previous failed container run. Because the profile root is `${HERMES_BROWSER_DATA_DIR:-${USERPROFILE:-${HOME}}/.hermes/.browser}` mounted at `/data`, the lock survived `docker compose down` even though no Chromium container was still running.

Fix:

- Updated `docker/hermes-browser/entrypoint.sh` to confirm `/data` is writable, then remove only `/data/SingletonLock`, `/data/SingletonSocket`, and `/data/SingletonCookie` before launching Chromium.
- Kept Chromium sandboxing enabled: no `--no-sandbox` flag was added.
- Strengthened `scripts/powershell/tests/handlers/Handler.HermesAgent.Tests.ps1` so the Chromium entrypoint contract requires stale singleton cleanup scoped to the dedicated `/data` container profile and continues to reject `--no-sandbox`.

Commands and results:

- RED focused Pester before entrypoint fix: `Handler.HermesAgent.Tests.ps1` reported 52 passed, 1 failed because `SingletonLock` cleanup was absent.
- GREEN focused Pester after entrypoint fix: `pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path './scripts/powershell/tests/handlers/Handler.HermesAgent.Tests.ps1' -Output Detailed"` exited 0 with 53 passed, 0 failed.
- Build: `docker compose -f docker/hermes-agent/compose.yml build chromium` exited 0 and built `local/hermes-browser:latest`.
- Runtime: `docker compose -f docker/hermes-agent/compose.yml up -d chromium` exited 0 and started `hermes-chromium`.
- Health: `docker compose -f docker/hermes-agent/compose.yml ps chromium` showed `hermes-chromium` as `Up ... (healthy)` with no host ports listed.
- CDP smoke: `docker compose -f docker/hermes-agent/compose.yml exec -T chromium curl -fsS http://127.0.0.1:9222/json/version` exited 0 and returned Chrome/150 `/json/version` metadata.
- Cleanup: `docker compose -f docker/hermes-agent/compose.yml stop chromium` stopped `hermes-chromium`, because Chromium was not running before this smoke test.

Scope note: stale lock cleanup is intentionally limited to the dedicated `/data` container profile root and does not touch the user's normal browser profile.
