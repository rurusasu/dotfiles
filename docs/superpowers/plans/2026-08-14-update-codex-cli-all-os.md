# Codex CLI All-OS Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every supported dotfiles update entry point refresh its package source before applying the environment, so macOS/Linux Codex follows updated `nixpkgs` and Windows Codex follows WinGet.

**Architecture:** Add one fail-closed shell helper for `nix flake update` and call it from all four Unix installers after Nix and checkout preparation but before activation. Extend the existing Phase 1 Winget handler with a Codex-only upgrade operation that runs only when `OpenAI.Codex` is installed, treating localized no-op output as success and preserving the existing install/verify/shim path.

**Tech Stack:** Bash, Bats, PowerShell, Pester, Nix flake tooling, WinGet.

## Global Constraints

- Unix update failure must stop before system or Home Manager activation.
- Windows update scope is `OpenAI.Codex`; do not unconditionally upgrade every Winget package.
- Windows Codex upgrade arguments must include `--id OpenAI.Codex`, `--exact`, `--silent`, `--accept-package-agreements`, and `--accept-source-agreements`.
- Existing Codex portable shim, verification, and non-Codex package behavior must remain intact.
- Do not automatically commit, push, or create a PR for generated lock/package changes.

---

### Task 1: Add failing Unix update-flow tests

**Files:**

- Modify: `tests/bash/install_macos.bats`
- Modify: `tests/bash/install_linux.bats`
- Modify: `tests/bash/install_nixos.bats`

**Interfaces:**

- Consumes: existing command-log stubs and `assert_log_order` helpers.
- Produces: regression coverage requiring `nix flake update` before each Unix activation path and preventing activation after update failure.

- [ ] **Step 1: Add success-order assertions**

Update the existing successful installer tests so their Nix stubs record `flake update`, then assert the exact update entry occurs before the existing activation entry. Use the corresponding activation markers for macOS (`darwin-rebuild`), NixOS (`nixos-rebuild`), and Home Manager (`homeConfigurations`).

```bash
assert_log_order \
  "nix flake update" \
  "switch --flake .#ubuntu --sudo"
```

- [ ] **Step 2: Add update-failure tests**

Make each test Nix stub return a non-zero status for exactly `flake update`, run the installer, assert a non-zero status, and assert the activation marker is absent.

```bash
if [[ $* == "flake update" ]]; then
  exit 41
fi
```

- [ ] **Step 3: Run the focused tests to verify they fail**

Run `bats tests/bash/install_macos.bats tests/bash/install_linux.bats tests/bash/install_nixos.bats`. Expected: the new update-order assertions fail because the installers do not yet invoke `nix flake update`.

- [ ] **Step 4: Commit the red tests**

```bash
git add tests/bash/install_macos.bats tests/bash/install_linux.bats tests/bash/install_nixos.bats
git commit -m "test: require flake updates before Unix activation"
```

### Task 2: Implement the shared Unix flake update helper

**Files:**

- Create: `scripts/sh/update-flake.sh`
- Modify: `scripts/sh/install-macos.sh`
- Modify: `scripts/sh/install-linux.sh`
- Modify: `scripts/sh/install-nixos.sh`
- Modify: `scripts/sh/install-home-manager.sh`

**Interfaces:**

- Consumes: `ROOT`, `dotfiles_have`, `dotfiles_log`, and `dotfiles_die` from `install-common.sh`.
- Produces: `dotfiles_update_flake <repo-root>`; it returns success only after `nix flake update` succeeds.

- [ ] **Step 1: Add the minimal helper**

Create a sourced shell helper with this contract:

```bash
dotfiles_update_flake() {
  local root="$1"
  dotfiles_have nix || dotfiles_die "Nix is required to update flake inputs."
  dotfiles_log "Updating Nix flake inputs..."
  (
    cd "$root" || dotfiles_die "Unable to enter dotfiles checkout: $root"
    nix flake update
  ) || dotfiles_die "Nix flake input update failed."
}
```

- [ ] **Step 2: Source and call the helper from every Unix installer**

Source `update-flake.sh` after `install-common.sh`, then call `dotfiles_update_flake "$ROOT"` in `main` after `dotfiles_link_checkout "$ROOT"` and before `apply_darwin_system`, `apply_linux_system`, `apply_nixos_system`, or `activate_home_manager`.

- [ ] **Step 3: Run the focused Bash tests to verify they pass**

Run `bats tests/bash/install_macos.bats tests/bash/install_linux.bats tests/bash/install_nixos.bats`. Expected: all focused installer tests pass, including the new ordering and fail-closed cases.

- [ ] **Step 4: Commit the Unix implementation**

```bash
git add scripts/sh/update-flake.sh scripts/sh/install-macos.sh scripts/sh/install-linux.sh scripts/sh/install-nixos.sh scripts/sh/install-home-manager.sh
git commit -m "fix: update flake inputs before Unix activation"
```

### Task 3: Add failing Windows Codex upgrade tests

**Files:**

- Modify: `scripts/powershell/tests/handlers/Handler.Winget.Tests.ps1`

**Interfaces:**

- Consumes: existing `WingetHandler`, Pester mocks, and package JSON fixtures.
- Produces: tests for installed Codex upgrade, missing Codex install fallback, no-op success, and real upgrade failure.

- [ ] **Step 1: Add an installed-Codex fixture and upgrade argument assertion**

Add a Pester test whose mocked package list contains `OpenAI.Codex`, whose installed list contains `OpenAI.Codex`, and whose `Invoke-Winget` mock captures the `upgrade` invocation. Assert the captured arguments contain:

```powershell
"upgrade", "--id", "OpenAI.Codex", "--exact", "--silent",
"--accept-package-agreements", "--accept-source-agreements"
```

- [ ] **Step 2: Add no-op and failure cases**

Add one test returning the existing localized no-update messages with a non-zero exit code and assert success. Add another returning an unrelated upgrade error and assert `SetupResult.Success` is `$false`.

- [ ] **Step 3: Run the focused Pester test to verify it fails**

Run `pwsh -NoProfile -Command "Invoke-Pester -Path ./scripts/powershell/tests/handlers/Handler.Winget.Tests.ps1 -Output Detailed"`. Expected: the new tests fail because `WingetHandler` has no explicit Codex upgrade call.

- [ ] **Step 4: Commit the red Windows tests**

```bash
git add scripts/powershell/tests/handlers/Handler.Winget.Tests.ps1
git commit -m "test: require explicit Windows Codex upgrades"
```

### Task 4: Implement the Windows Codex upgrade path

**Files:**

- Modify: `scripts/powershell/handlers/Handler.Winget.ps1`

**Interfaces:**

- Consumes: parsed Winget package objects and the existing installed-ID discovery.
- Produces: a Codex-only upgrade before normal package processing, with no-op success and failure propagation through `SetupResult`.

- [ ] **Step 1: Add a Codex upgrade method**

Implement a private method that accepts the parsed Codex package object and invokes `Invoke-Winget` with the exact upgrade arguments. Treat output matching the existing `IsAlreadyInstalledInstallFailure` no-op messages as successful; return `$false` for all other non-zero exits.

- [ ] **Step 2: Invoke it only for installed `OpenAI.Codex`**

After `$installedIds` is obtained and before normal install/verification processing, find the exact package ID. If it is installed, run the method. On failure, return `CreateFailureResult` immediately; on success, refresh the process PATH and portable link before the normal verification loop. If it is not installed, skip the explicit upgrade and let existing install behavior handle it.

- [ ] **Step 3: Run the focused Pester test to verify it passes**

Run `pwsh -NoProfile -Command "Invoke-Pester -Path ./scripts/powershell/tests/handlers/Handler.Winget.Tests.ps1 -Output Detailed"`. Expected: the focused Winget handler suite passes with zero failed tests.

- [ ] **Step 4: Commit the Windows implementation**

```bash
git add scripts/powershell/handlers/Handler.Winget.ps1
git commit -m "fix: explicitly upgrade Codex with winget"
```

### Task 5: Run complete validation and inspect the final diff

**Files:**

- Inspect: all changed files and commits from Tasks 1–4.
- Observe: `flake.lock` and generated Windows package metadata as runtime update outputs; do not edit them directly in this feature change.

- [ ] **Step 1: Run all Bash tests**

Run `bats tests/bash`. Expected: exit code 0 and no failed tests.

- [ ] **Step 2: Run all PowerShell tests and analyzer**

Run `pwsh -NoProfile -Command "& ./scripts/powershell/tests/Invoke-Tests.ps1 -MinimumCoverage 0"`. Expected: exit code 0 and no failed Pester tests or analyzer errors.

- [ ] **Step 3: Run formatting checks**

Run `nix fmt -- --fail-on-change`. Expected: formatter exits 0 without modifying files.

- [ ] **Step 4: Review status and diff**

Run:

```bash
git status --short --branch
git diff main...HEAD --stat
git diff main...HEAD -- scripts/sh tests/bash scripts/powershell/handlers/Handler.Winget.ps1 scripts/powershell/tests/handlers/Handler.Winget.Tests.ps1
```

Confirm only the approved Unix update flow, Windows Codex update flow, tests, and the already-committed design/plan artifacts are present.
