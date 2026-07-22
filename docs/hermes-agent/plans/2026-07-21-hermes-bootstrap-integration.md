# Hermes Installer Integration and Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect the common container bootstrap to `install.sh` and `install.cmd`, delete the divergent OS-specific provisioning logic, migrate the real Hermes runtime safely, and verify every root/profile service with the confirmed 1Password items.

**Architecture:** Unix and PowerShell adapters invoke the bootstrap's non-secret `secret-plan`, fetch each declared item with host `op`, and stream versioned NDJSON to `docker compose run -T hermes-bootstrap`. Existing installers continue owning host prerequisites and Docker startup. The common bootstrap must succeed before Compose recreates Hermes; old shell and PowerShell config writers are removed only after contract, migration, and live acceptance tests cover their behavior.

**Tech Stack:** Bash, Bats, PowerShell 7, Pester 5/6, 1Password CLI, Docker Compose, Hermes Agent CLI, Taskfile

## Global Constraints

- Keep `install.sh` and `install.cmd` as the only documented full-machine entrypoints.
- Keep `HermesAgentHandler` at Phase 2, non-admin, Order 56 so 1Password desktop integration remains available on Windows.
- Build and validate the Hermes image before requesting secrets; recreate services only after bootstrap success.
- Require 1Password and all six declared items. Remove generated dashboard-password fallback and stale-secret fallback.
- Do not write the NDJSON payload to disk or pass values in process arguments.
- Preserve the Docker runner abstraction used for Linux/NixOS docker-group execution.
- Do not edit or regenerate root/profile declarative YAML, cron, scripts, policy, or MCP blocks on the host.
- Keep unrelated installer behavior and current browser services unchanged.
- Document and preserve the source-repository gate from `distribution-validation-design.md`: exact-head local `full` validation plus `PASS_REMOTE`, or `PASS_LOCAL_FALLBACK` only for explicit GitHub billing startup evidence. Missing workflow evidence is never treated as billing.

---

## Task 1: Replace the Unix provisioning helpers with a streaming adapter

**Files:**

- Modify: `scripts/sh/hermes-agent.sh`
- Modify: `tests/bash/hermes_agent.bats`

- [ ] Replace existing success-path tests with failing contract tests for: secret-plan retrieval, six `op item get --format json` calls, NDJSON record order, bootstrap exit propagation, no `compose up` after failure, Compose recreation after success, Docker runner forwarding, and no token in captured command arguments or logs.

- [ ] Retain focused tests for `dotfiles_hermes_data_dir`, `dotfiles_hermes_browser_data_dir`, and runtime-directory creation because those remain host responsibilities.

- [ ] Define the shared shell interfaces:

```bash
dotfiles_hermes_secret_plan()              # args: docker_runner compose_file
dotfiles_hermes_emit_secret_payload()      # args: compact_plan_json
dotfiles_hermes_run_bootstrap()            # args: docker_runner compose_file
dotfiles_hermes_start_stack()              # args: docker_runner compose_file
dotfiles_hermes_show_compose_diagnostics() # args: docker_runner compose_file
```

- [ ] Implement `dotfiles_hermes_secret_plan` as:

```text
docker compose -f <compose> run --rm --no-deps -T hermes-bootstrap secret-plan
```

Validate the output with `jq -e` and require schema version `1`, a non-empty `items` array, unique keys, and account/vault/item strings.

- [ ] Implement `dotfiles_hermes_emit_secret_payload` as a pipeline producer. Emit one header record, iterate the plan in declared order, run `op item get <item> --account <account> --vault <vault> --format json`, wrap the raw item object in one compact item record with `jq -c`, then emit one end record.

- [ ] Enable `pipefail` and pipe the producer directly to `docker compose -f "$compose_file" run --rm --no-deps -T hermes-bootstrap apply`. Capture and return the Docker process status without echoing the payload. A failed `op` call must close stdin and make the adapter non-zero.

- [ ] Implement `dotfiles_hermes_start_stack` in this order: prepare host data/browser directories, `docker compose config --quiet`, `docker compose build hermes hermes-bootstrap`, run bootstrap, then `docker compose up -d --force-recreate`. On failure, print redacted Compose diagnostics and leave the existing gateway running.

- [ ] Delete shell helpers that parse or write dashboard, Slack, model, profile, or `.env` content, including `dotfiles_hermes_ensure_dashboard_auth`, `dotfiles_hermes_ensure_slack_environment`, and `dotfiles_hermes_ensure_runtime_configuration` plus their private dependencies.

- [ ] Run Bats and require the new adapter cases to pass.

```bash
bats tests/bash/hermes_agent.bats
```

## Task 2: Route every Unix installer through the shared adapter

**Files:**

- Modify: `scripts/sh/install-macos.sh`
- Modify: `scripts/sh/install-linux.sh`
- Modify: `scripts/sh/install-nixos.sh`
- Modify: `tests/bash/hermes_agent.bats`

- [ ] Add source-level tests that each installer calls `dotfiles_hermes_start_stack` exactly once and no longer defines a local `start_hermes_stack`.

- [ ] Remove the duplicated `start_hermes_stack` functions from macOS, Linux, and NixOS.

- [ ] After the existing OS setup and chezmoi phase, call the shared adapter with the platform's Docker runner and `docker/hermes-agent/compose.yml`.

```bash
# macOS
dotfiles_hermes_start_stack docker "$DOTFILES_ROOT/docker/hermes-agent/compose.yml"

# Linux and NixOS
dotfiles_hermes_start_stack docker_command "$DOTFILES_ROOT/docker/hermes-agent/compose.yml"
```

- [ ] Keep current Docker daemon setup and runner behavior. Ensure the `op` and `jq` checks occur in host preflight with an error naming the missing command.

- [ ] Run shell syntax and Bats tests.

```bash
bash -n scripts/sh/hermes-agent.sh scripts/sh/install-macos.sh scripts/sh/install-linux.sh scripts/sh/install-nixos.sh
bats tests/bash/hermes_agent.bats
```

- [ ] Verify the call chain remains `install.sh -> install-<os>.sh -> dotfiles_hermes_start_stack` by running each installer's mocked test path; do not execute a real Nix rebuild in unit tests.

## Task 3: Add a PowerShell streaming adapter

**Files:**

- Create: `scripts/powershell/lib/HermesBootstrap.ps1`
- Create: `scripts/powershell/tests/lib/HermesBootstrap.Tests.ps1`
- Modify: `scripts/powershell/lib/AGENTS.md`

- [ ] Write failing Pester tests for the same contract as Bash: plan validation, exact item lookup arguments, header/item/end order, direct stdin streaming, no payload file, no secret-bearing process arguments, bootstrap exit propagation, redacted stderr, and successful result metadata.

- [ ] Define these public functions:

```powershell
function Get-HermesBootstrapSecretPlan {
    param([string]$ComposeFile)
}

function Invoke-HermesBootstrap {
    param(
        [string]$ComposeFile,
        [string]$DataDir,
        [scriptblock]$InvokeOnePasswordItem = $script:DefaultOnePasswordInvoker
    )
}
```

- [ ] `Get-HermesBootstrapSecretPlan` invokes Docker Compose with an argument array and parses the compact JSON with `ConvertFrom-Json`. Reject unsupported schema versions, duplicates, blank fields, and unexpected item count before calling `op`.

- [ ] `Invoke-HermesBootstrap` creates `System.Diagnostics.ProcessStartInfo` for `docker compose -f <file> run --rm --no-deps -T hermes-bootstrap apply`, sets `UseShellExecute = $false`, redirects standard input/output/error, and appends only non-secret arguments through `ArgumentList`.

- [ ] Start the Docker process before retrieving item data. Write each compact JSON record directly to `StandardInput`, dispose each raw item object after serialization, close stdin in `finally`, drain stdout/stderr asynchronously to avoid deadlock, and return a structured success/changed/message result.

- [ ] Retrieve item JSON with host `op item get <item> --account <account> --vault <vault> --format json`. Never add `--reveal` for full item JSON and never convert a secret field into a process argument.

- [ ] Redact discovered field values from Docker output before writing it through `SetupContext`; do not include item JSON in thrown exceptions.

- [ ] Update `scripts/powershell/lib/AGENTS.md` to state that this module owns transport only and the container owns interpretation and persistence.

- [ ] Run focused Pester tests.

```bash
pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1 -Path scripts/powershell/tests/lib/HermesBootstrap.Tests.ps1 -MinimumCoverage 0
```

## Task 4: Reduce `HermesAgentHandler` to orchestration

**Files:**

- Modify: `scripts/powershell/handlers/Handler.HermesAgent.ps1`
- Modify: `scripts/powershell/install.admin.ps1`
- Modify: `scripts/powershell/tests/handlers/Handler.HermesAgent.Tests.ps1`

- [ ] Rewrite handler tests around the new behavior before deleting old methods. Preserve tests for constructor metadata, Phase 2 ordering, `CanApply`, data/browser directory creation, Compose build/up failure, browser viewer URL, and setup result reporting.

- [ ] Add tests that bootstrap failure prevents `compose up`, success invokes `compose up -d --force-recreate`, and no admin phase performs an `op` call.

- [ ] Dot-source `scripts/powershell/lib/HermesBootstrap.ps1` from the same loader path as the other PowerShell libraries.

- [ ] Reduce `Apply()` to: resolve Compose and data paths; create data/browser directories; run `docker compose config --quiet`; build `hermes` and `hermes-bootstrap`; call `Invoke-HermesBootstrap`; recreate services; return URLs and changed status.

- [ ] Remove the old methods for dashboard generation, 1Password field parsing, GitHub/Slack env provisioning, named-profile Git initialization, root-home layout generation, lifelog bootstrap, cron/script generation, YAML block mutation, model/MCP/Slack config mutation, and duplicated env-file merging.

- [ ] Preserve handler options that control whether Hermes itself runs and browser/data paths. Remove obsolete options that allowed missing 1Password, generated dashboard fallback, root/profile Slack fallback, or per-OS source ownership.

- [ ] Confirm `scripts/powershell/install.admin.ps1` still schedules `HermesAgentHandler` in Phase 2 after Nix rebuild and outside elevation. Make no change to `install.cmd -> install.ps1 -> install.admin.ps1` routing beyond loading the adapter.

- [ ] Run the focused suite and inspect the handler size reduction.

```bash
pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1 -Path scripts/powershell/tests/handlers/Handler.HermesAgent.Tests.ps1 -MinimumCoverage 0
pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1 -Path scripts/powershell/tests/lib/HermesBootstrap.Tests.ps1 -MinimumCoverage 0
wc -l scripts/powershell/handlers/Handler.HermesAgent.ps1
```

Expected: all rewritten tests pass and the handler contains orchestration rather than generated content templates.

## Task 5: Update Taskfile and operator documentation

**Files:**

- Modify: `Taskfile.yml`
- Modify: `docs/hermes-agent/profile-home-layout.md`
- Modify: `docs/hermes-agent/browser-mcp.md`
- Create: `docs/hermes-agent/bootstrap.md`
- Modify: `docs/chezmoi/secrets.md`
- Modify: `docs/architecture.md`

- [ ] Add `hermes:bootstrap` to build the image and invoke the current host adapter without starting an unrelated full machine rebuild. On Unix it sources `scripts/sh/hermes-agent.sh`; on Windows the documented command invokes the handler through `install.cmd` because PowerShell Taskfile execution cannot share Bash functions.

- [ ] Remove `hermes:profile:init` and documentation that initializes profile Git repositories. Keep `hermes:<profile>:up/down/restart/logs` commands.

- [ ] Document the supported full paths:

```text
install.sh -> OS installer -> shell adapter -> hermes-bootstrap -> compose up
install.cmd -> install.ps1 -> install.admin.ps1 -> HermesAgentHandler -> PowerShell adapter -> hermes-bootstrap -> compose up
```

- [ ] In `profile-home-layout.md`, document `/opt/data` as runtime root, official named distributions under `profiles/`, shared repositories under `shared/`, and the absence of legacy runtime paths under `core/` after migration.

- [ ] In `bootstrap.md`, document prerequisites, the six 1Password item names and fields without values, failure exit codes, transaction recovery, lock contention, migration conflicts, rerun behavior, and redacted diagnostics.

- [ ] Update Browser MCP docs to use `/opt/data/shared/lifelog` and note that browser services are not dependencies of the one-shot bootstrap service.

- [ ] Update secrets docs to state that `GitHubUsedOpenClawPAT/credential` is mandatory, shared to all Hermes `.env` files, and consumed by `gh-wrapper.sh`; remove the old `Private/GitHubUsedUserPAT` reference.

- [ ] Update `docs/architecture.md` with source repository ownership boundaries and link the approved design plus all three implementation plans.

- [ ] Link `docs/hermes-agent/distribution-validation-design.md` from `bootstrap.md` and document the operator states `PASS_REMOTE`, `PASS_LOCAL_FALLBACK`, `FAIL_VALIDATION`, `FIX_FAILED`, `ENV_BLOCKED`, `REMOTE_PENDING`, `REMOTE_UNKNOWN`, `STALE_EVIDENCE`, and `INTERNAL_ERROR`, including the two-round agent repair limit and the rule that missing runs never authorize fallback.

- [ ] Run Markdown and repository lint checks scoped to the changed docs.

```bash
pre-commit run --files docs/hermes-agent/bootstrap-design.md docs/hermes-agent/bootstrap.md docs/hermes-agent/profile-home-layout.md docs/hermes-agent/browser-mcp.md docs/chezmoi/secrets.md docs/architecture.md
```

## Task 6: Exercise migration with fixture runtime homes

**Files:**

- Modify: `docker/hermes-agent/bootstrap/tests/integration/test_bootstrap_flow.py`
- Modify: `tests/bash/hermes_agent.bats`
- Modify: `scripts/powershell/tests/handlers/Handler.HermesAgent.Tests.ps1`

- [ ] Add a fixture matching the current runtime shape: default profile only, existing root `.env`, optional named-profile directories without distribution metadata, `/opt/data/core/lifelog` as a real checkout, and mutable memory/session sentinels.

- [ ] Verify first migration moves the lifelog checkout to `/opt/data/shared/lifelog`, removes the legacy path, installs three distributions, applies root-owned files, preserves all sentinels and unmanaged env keys, and writes each profile's own Slack tokens.

- [ ] Add a fixture where both old and new lifelog paths contain data. Assert migration exit code `5`, no distribution/env changes, no Compose recreation, and a conflict message naming both paths.

- [ ] Inject a failure after each local apply stage and assert rollback of root files, profiles, shared migration, symlink, ownership state, and env files. Assert a previously successful remote lifelog push is not reversed.

- [ ] Run the bootstrap twice and assert the second run reports no root/profile/env/migration changes and does not create a Git commit for unchanged lifelog content.

- [ ] Run all focused local suites.

```bash
task hermes:bootstrap:test
bats tests/bash/hermes_agent.bats
pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1 -Path scripts/powershell/tests/handlers/Handler.HermesAgent.Tests.ps1 -MinimumCoverage 0
pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1 -Path scripts/powershell/tests/lib/HermesBootstrap.Tests.ps1 -MinimumCoverage 0
docker compose -f docker/hermes-agent/compose.yml config --quiet
```

## Task 7: Perform live acceptance with the confirmed 1Password items

**Runtime:** host `~/.hermes` mounted at container `/opt/data`

- [ ] Confirm Docker, `op`, and GitHub access without printing values.

```bash
docker info
op item get GitHubUsedOpenClawPAT --account my.1password.com --vault openclaw --format json | jq -e '.fields[] | select(.label == "credential") | .value | length > 0' >/dev/null
```

- [ ] Back up `~/.hermes` using a filesystem snapshot or a local archive outside the runtime directory. Do not add the backup to Git.

- [ ] Run the supported installer for the current host. On macOS use `./install.sh`; on Windows use `install.cmd`. Capture ordinary logs and verify no token, Slack credential, dashboard password, or raw item JSON appears.

- [ ] Verify the final profile and repository layout.

```bash
docker exec hermes /opt/hermes/.venv/bin/hermes profile list
docker exec hermes test -d /opt/data/shared/lifelog/.git
docker exec hermes sh -c 'test "$(readlink /opt/data/core/lifelog)" = ../shared/lifelog'
docker exec hermes test ! -e /opt/data/.git
docker exec hermes test ! -e /opt/data/profiles/rick/.git
docker exec hermes test ! -e /opt/data/profiles/hoffman/.git
docker exec hermes test ! -e /opt/data/profiles/risarisa/.git
```

Expected: profile list contains default, rick, hoffman, and risarisa; only shared lifelog is a Git checkout.

- [ ] Verify GitHub auth in every active profile context without displaying the token.

```bash
docker exec -e HERMES_HOME=/opt/data hermes gh auth status
docker exec -e HERMES_HOME=/opt/data/profiles/rick hermes gh auth status
docker exec -e HERMES_HOME=/opt/data/profiles/hoffman hermes gh auth status
docker exec -e HERMES_HOME=/opt/data/profiles/risarisa hermes gh auth status
```

Expected: all four commands authenticate as `rurusasu`.

- [ ] Verify root/profile environment permissions and required key names without printing values.

```bash
docker exec hermes sh -c 'for f in /opt/data/.env /opt/data/profiles/rick/.env /opt/data/profiles/hoffman/.env /opt/data/profiles/risarisa/.env; do test "$(stat -c %a "$f")" = 600; grep -q "^GH_TOKEN=" "$f"; grep -q "^SLACK_BOT_TOKEN=" "$f"; done'
```

- [ ] Verify root API/dashboard/browser and all profile gateways.

```bash
docker compose -f docker/hermes-agent/compose.yml ps
curl --fail --silent http://127.0.0.1:8642/health >/dev/null
curl --fail --silent http://127.0.0.1:6080/ >/dev/null
docker exec hermes /opt/hermes/.venv/bin/hermes -p rick gateway status
docker exec hermes /opt/hermes/.venv/bin/hermes -p hoffman gateway status
docker exec hermes /opt/hermes/.venv/bin/hermes -p risarisa gateway status
```

- [ ] Confirm root and each named Slack app can receive one mention and continue its thread without a repeated mention. Confirm profile responses come from the intended Slack app identity.

- [ ] Run the focused bootstrap a second time and confirm the summary is idempotent and no new lifelog sync commit is created.

## Task 8: Run full verification and publish the dotfiles change

**Files:** all changed dotfiles repository paths

- [ ] Run focused tests, full lint, and secret scans.

```bash
task hermes:bootstrap:test
bats tests/bash
pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1 -MinimumCoverage 0
task lint:all
pre-commit run --all-files
git diff --check
```

- [ ] Inspect `git status --short` and `git diff --stat`; stage only Hermes bootstrap, adapter, test, Taskfile, and documentation files.

- [ ] Commit through the repository's supported commit task when it targets this worktree; otherwise run the equivalent scoped pre-commit checks and a path-scoped Git commit so another checkout is not staged.

```bash
git commit -m "feat: add OS-independent Hermes bootstrap"
```

- [ ] Push `codex/hermes-bootstrap` and open a PR that links the four merged source-repository PRs and includes fixture plus live acceptance evidence.

- [ ] Wait for all GitHub Actions checks, address review conversations, rerun affected checks, and merge with the repository's allowed merge method. If GitHub explicitly reports a billing startup block, require an exact-head clean local run of every command above, post a redacted evidence comment, re-read the PR head, and apply the approved local fallback; absent explicit billing evidence, leave the PR unmerged.

- [ ] After merge, run one final `hermes-bootstrap validate` against the live runtime and record only target names, versions, commit SHAs, and health states.

## Completion Criteria

- `install.sh` and `install.cmd` both reach the same container implementation.
- Shell and PowerShell contain transport/orchestration only; no duplicate env/config/Git merge logic remains.
- Missing or invalid 1Password/GitHub data fails before service recreation.
- Existing runtime data migrates to the approved root/profile/shared layout and survives rollback tests.
- Root plus all named profiles authenticate `gh`, use separate Slack credentials, and pass gateway health checks.
- A second run is idempotent, all local/hosted checks pass, and the dotfiles PR is merged.
