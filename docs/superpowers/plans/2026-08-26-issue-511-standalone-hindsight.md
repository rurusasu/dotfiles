# Issue #511 Standalone Hindsight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run Hindsight as an independent Docker service shared by host Codex, Tart Codex, and Hermes.

**Architecture:** Move Hindsight into its own Compose project and task namespace, join it to Hermes through an external network, and configure Codex with managed provider-neutral hooks. Hermes probes Hindsight but never owns its lifecycle.

**Tech Stack:** Docker Compose, Bash/Bats, PowerShell/Pester, Python, chezmoi, Task

**Spec:** `docs/superpowers/specs/2026-08-26-issue-511-optional-profiles-shared-hindsight-design.md`

## Global Constraints

- Bind the host API to loopback and retain existing persistent data.
- Keep the v0.9.1 acceptance payload compatible with the `fact` retain contract.
- Never allow tests to resolve the real host Ollama executable.

---

### Task 1: Repair test executable isolation

- [ ] Use the existing hanging macOS installer test as the failing reproduction.
- [ ] Inject exact stub paths for Ollama and curl in `tests/bash/macos_installer.bats`.
- [ ] Run the formerly hanging test alone and prove it completes without a host Ollama process.

### Task 2: Extract the Hindsight Compose project

- [ ] Add Bats/static Compose tests for independent service name, loopback ports, data root, healthcheck, and external shared network.
- [ ] Confirm tests fail before adding the new project.
- [ ] Create `docker/hindsight/compose.yml` and environment/config assets; remove the service and data ownership from Hermes Compose.
- [ ] Connect Hermes services to the external memory network without adding lifecycle dependencies.
- [ ] Run `docker compose config --quiet` for both projects and focused tests.

### Task 3: Add independent lifecycle and acceptance tasks

- [ ] Add failing task/static tests for `hindsight:up`, `down`, `status`, `logs`, and `verify`.
- [ ] Create `taskfiles/hindsight/taskfile.yml` and platform adapters that prepare Ollama/models and manage only Hindsight.
- [ ] Move acceptance ownership out of Hermes; keep Hermes integration verification scoped to reachability and bank behavior.
- [ ] Remove Hindsight start/stop/restart calls from Hermes Bash and PowerShell handlers.
- [ ] Run Bats, Pester, Python tests, and Compose validation.

### Task 4: Manage Codex memory hooks

- [ ] Add tests for merging SessionStart/UserPromptSubmit/Stop with existing hooks and for shared-bank/runtime metadata.
- [ ] Confirm the tests fail.
- [ ] Add chezmoi-managed hook scripts/config and merge them into `chezmoi/dot_codex/hooks.json.tmpl`.
- [ ] Configure host endpoint and shared bank defaults without embedding secrets.
- [ ] Run hook unit tests with a stub Hindsight endpoint and chezmoi template validation.

### Task 5: Validate and checkpoint

- [ ] Run focused Bash/PowerShell suites, Compose config validation, and `task lint:all`.
- [ ] Review the diff for lifecycle coupling and persistence-path regressions.
- [ ] Stage only owned files and commit with `task commit -- "feat: run hindsight independently"`.
