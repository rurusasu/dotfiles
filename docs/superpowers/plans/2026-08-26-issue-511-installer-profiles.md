# Issue #511 Installer Profiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the default Windows installation core-only and remove Claude and TablePlus from managed dotfiles.

**Architecture:** Expand `With*` dependencies in `install.ps1`, pass feature state through `SetupContext.Options`, and filter package handlers using catalog-generated feature metadata. Delete Claude ownership at each declarative source and move reusable skills to `~/.agents/skills`.

**Tech Stack:** PowerShell 7/Pester, Nix, chezmoi, JSON, Bats

**Spec:** `docs/superpowers/specs/2026-08-26-issue-511-optional-profiles-shared-hindsight-design.md`

## Global Constraints

- Preserve unrelated worktree changes and use `task commit --` for commits.
- Add a failing focused test before each behavior change.
- Generate package JSON from `nix/packages/sets.nix`; do not hand-maintain divergent catalogs.

---

### Task 1: Define and propagate feature profiles

- [ ] Add Pester coverage proving the default is core-only and dependency expansion for `WithOllama`, `WithDocker`, and `WithHermes`.
- [ ] Run the focused Pester tests and confirm they fail.
- [ ] Add switches to `scripts/powershell/install.ps1`, normalize effective options, and preserve them across elevated phases.
- [ ] Update Docker and Hermes `CanApply` conditions to require effective feature flags and remove interactive consent ownership.
- [ ] Run focused Pester tests and `task test:powershell`.

### Task 2: Filter optional package installation

- [ ] Add package-catalog and Winget handler tests for feature metadata and filtering of Ollama, Docker, Chrome, and Discord.
- [ ] Run the focused tests and confirm failure.
- [ ] Extend `nix/packages/sets.nix` and `nix/packages/winget.nix` to emit feature metadata; update `Handler.Winget.ps1` to filter it from effective options.
- [ ] Gate Chromium/Playwright pnpm installation behind `WithHermes` using the same profile model.
- [ ] Regenerate JSON and run Nix evaluation plus package-catalog/handler tests.

### Task 3: Remove Claude and TablePlus

- [ ] Add repository assertions that forbidden package IDs, Claude handler/config paths, ACP package, and editor extensions are absent.
- [ ] Confirm the new assertions fail.
- [ ] Remove Claude/TablePlus entries from the package SSOT and generated catalogs.
- [ ] Delete Claude-specific handlers, tests, chezmoi data/scripts/config, bootstrap logic, editor/Neovim/PowerShell integrations, and stale CI/docs references.
- [ ] Move reusable skills to `chezmoi/dot_agents/skills`; rename Codex permission-policy assets to provider-neutral names.
- [ ] Run chezmoi, Nix, Bash, and PowerShell focused tests and inspect `rg -ni 'claude|tableplus'` exceptions.

### Task 4: Validate and checkpoint

- [ ] Run `nix fmt`, `task lint:all`, relevant Bats, and `task test:powershell`.
- [ ] Review the diff for generated-file consistency and accidental deletions.
- [ ] Stage only owned files and commit with `task commit -- "feat: add explicit installer profiles"`.
