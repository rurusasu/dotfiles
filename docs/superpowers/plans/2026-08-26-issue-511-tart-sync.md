# Issue #511 Tart Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Start a minimal Tart VM with current dotfiles and shared host Hindsight memory.

**Architecture:** Add a host `tart:run` orchestration task and a guest idempotent sync script. The guest compares Git hashes before applying; SSH reverse forwarding exposes only the host loopback Hindsight endpoint inside the guest.

**Tech Stack:** Tart, SSH, Bash/Bats, Git, chezmoi, Nix/Homebrew

**Spec:** `docs/superpowers/specs/2026-08-26-issue-511-optional-profiles-shared-hindsight-design.md`

## Global Constraints

- The applied hash changes only after a successful dotfiles apply.
- The VM profile contains Neovim, WezTerm, chezmoi, Codex, and required base tools only.
- Hindsight remains unreachable from the LAN.

---

### Task 1: Specify the minimal Tart profile

- [ ] Add failing Nix/catalog tests for the exact Tart package profile.
- [ ] Define a Tart-specific package set and guest apply entry point without changing host defaults.
- [ ] Run Nix evaluation and package tests.

### Task 2: Implement hash-aware guest synchronization

- [ ] Add Bats tests for initial clone, unchanged remote skip, changed remote apply, failed apply retry, and explicit ref/repository configuration.
- [ ] Confirm each behavior fails before implementation.
- [ ] Add an idempotent guest sync script using `git ls-remote`, a local checkout, and an applied-hash state file.
- [ ] Ensure atomic state-file replacement only after successful install/apply.
- [ ] Run focused Bats tests.

### Task 3: Add Tart startup orchestration

- [ ] Add failing Bats/static task tests for `tart:run`, VM preparation, SSH readiness, guest sync invocation, and reverse forwarding.
- [ ] Extend Tart scripts/tasks to start the VM and establish guest `127.0.0.1:8888` to host `127.0.0.1:8888` forwarding.
- [ ] Make missing Hindsight non-fatal to VM boot but explicit in status output; make sync failures fatal.
- [ ] Run Tart installer/startup Bats tests.

### Task 4: Validate and checkpoint

- [ ] Run all Tart Bats tests, shell formatting/lint, Nix evaluation, and task schema validation.
- [ ] Review the diff for hash-state correctness, quoting, and unintended package expansion.
- [ ] Stage only owned files and commit with `task commit -- "feat: sync minimal tart vm on startup"`.
