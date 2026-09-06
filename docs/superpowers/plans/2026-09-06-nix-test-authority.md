# Nix Test Authority Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Nix the authoritative test layer for Nix configuration and Home Manager composition, standardize every host on a `default.nix` plus `configuration.nix` layout, move Darwin/WSL branches out of `common.nix`, and remove duplicate Nix assertions from Bats.

**Architecture:** `nix-unit` will evaluate Home Manager modules and host composition directly with fixed test inputs and will retain source-level layout checks. Every `nix/hosts/<host>/default.nix` will be a small integration entry point importing `configuration.nix`. Bats will remain only for shell, installer, external-command, and runtime contracts. `common.nix` will contain shared user configuration while each OS module owns its package and platform options.

**Tech Stack:** Nix flakes, nix-unit, Home Manager, NixOS/nix-darwin modules, Bats for non-Nix contracts, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-06-nix-test-authority-design.md`

## Global Constraints

- `nix/tests/home/` is authoritative for Home Manager Nix configuration tests.
- Bats is limited to shell/installer/external-process/runtime contracts.
- Tests must be deterministic and must not use secrets, network, activation, or external commands.
- Preserve unrelated dirty files in the primary checkout.
- Use `origin/main` as the base and merge only after hosted checks and review requirements pass.
- Keep `nix/home/darwin.nix`, `linux.nix`, and `wsl.nix` importing `./common.nix`.
- Keep `nix/hosts/<host>/default.nix` as the host integration entry point and `configuration.nix` as the host-specific configuration file.

---

### Task 1: Add failing Nix-native ownership and composition tests

**Files:**

- Modify: `nix/flakes/tests.nix`
- Create: `nix/tests/home/platform-boundary.nix`
- Create: `nix/tests/home/composition.nix`
- Test: `nix flake check --all-systems --no-build --no-write-lock-file`

**Interfaces:**

- `nix/flakes/tests.nix` registers both the existing import-boundary attrset and the new test attrsets.
- `composition.nix` receives the flake inputs needed to construct `home-manager.lib.homeManagerConfiguration` with fixed user/home values.

- [ ] **Step 1: Write the failing platform-boundary tests**

  Add Nix expressions that read `nix/home/common.nix` and assert that the shared module does not contain `isWSL`, `isDarwin`, `/opt/homebrew`, `HOMEBREW_AUTO_UPDATE_SECS`, or `TERMINFO_DIRS`. Assert that the OS entry modules retain the common import.

- [ ] **Step 2: Write the failing composition tests**

  Build test Home Manager configurations for Darwin, native Linux, and WSL with fixed `home.username`, `home.homeDirectory`, and `installFeatures`. Assert shared aliases/session variables on every profile; Darwin-only packages, paths, variables, and `zsh.envExtra`; WSL-only variables/services and package exclusions; and absence of Darwin/WSL values from the wrong profile.

- [ ] **Step 3: Register the suites**

  Pass the flake inputs into the composition test and merge both test attrsets into `nix-unit.tests` without changing the existing `test`-prefixed naming contract.

- [ ] **Step 4: Run the focused check and verify RED**

  Run:

  ```bash
  nix flake check --all-systems --no-build --no-write-lock-file
  ```

  Expected: failure caused by current Darwin/WSL branches in `common.nix` or missing composition ownership, not by a syntax/import error.

- [ ] **Step 5: Commit the failing test stage**

  ```bash
  git add nix/flakes/tests.nix nix/tests/home/platform-boundary.nix nix/tests/home/composition.nix
  git commit -m "test(nix): define Home Manager ownership boundaries"
  ```

### Task 2: Move OS-specific Home Manager configuration to OS modules

**Files:**

- Modify: `nix/home/common.nix`
- Modify: `nix/home/darwin.nix`
- Modify: `nix/home/linux.nix`
- Modify: `nix/home/wsl.nix`
- Test: `nix flake check --all-systems --no-build --no-write-lock-file`

**Interfaces:**

- Each OS module imports `./common.nix` and owns its own package/session/platform options.
- `installFeatures` remains available to Darwin standalone and nix-darwin callers.

- [ ] **Step 1: Move Darwin package selection and extras**

  Import `sets.nix` in `darwin.nix`, assign `sets.darwinHomePackagesForInstallFeatures installFeatures` plus `pkgs.coreutils` and `pkgs.wezterm.terminfo` to `home.packages`, and move the Darwin session variables, Homebrew PATH, and terminfo `programs.zsh.envExtra` there.

- [ ] **Step 2: Move Linux and WSL package selection**

  Assign `sets.all` in `linux.nix`. Assign `sets.allWithout [ "discord" "ollama" ]` in `wsl.nix` and remove the `isWSL` argument from the shared module.

- [ ] **Step 3: Remove platform branches from common.nix**

  Remove the package catalog resolver from `common.nix` if it is no longer needed there, remove `isWSL`, Darwin predicates, Darwin-only environment variables, and Darwin-only paths. Preserve common packages/paths, shell integration, bootstrap identity, and stateVersion.

- [ ] **Step 4: Run the new tests and verify GREEN**

  Run the focused Nix check. Expected: all new platform-boundary and composition tests pass, proving the refactor satisfies the RED tests.

- [ ] **Step 5: Commit the module refactor**

  ```bash
  git add nix/home/common.nix nix/home/darwin.nix nix/home/linux.nix nix/home/wsl.nix
  git commit -m "refactor(nix): isolate Home Manager OS modules"
  ```

### Task 3: Split the Darwin host entry point from its configuration

**Files:**

- Modify: `nix/hosts/darwin/default.nix`
- Create: `nix/hosts/darwin/configuration.nix`
- Modify: `nix/flakes/darwin.nix`
- Create or modify: `nix/tests/hosts/darwin-layout.nix`
- Modify: `nix/flakes/tests.nix`
- Test: `nix build .#checks.x86_64-linux.nix-unit --no-write-lock-file`

**Interfaces:**

- `nix/hosts/darwin/default.nix` imports `./configuration.nix` and contains no Darwin system option implementation.
- `nix/hosts/darwin/configuration.nix` provides the same nix-darwin module options currently provided by the monolith.
- `nix/flakes/darwin.nix` consumes `../hosts/darwin` so directory resolution selects `default.nix`.

- [ ] **Step 1: Write the failing host-layout tests**

  Add a Nix test that asserts `configuration.nix` exists, `default.nix` imports `./configuration.nix`, the flake consumes the Darwin host directory, and Darwin system options occur in `configuration.nix` rather than the entry point.

- [ ] **Step 2: Run the host-layout test and verify RED**

  Run:

  ```bash
  nix build .#checks.x86_64-linux.nix-unit --no-write-lock-file
  ```

  Expected: the new layout assertions fail against the current monolithic `default.nix`.

- [ ] **Step 3: Move the Darwin module implementation**

  Move the current module body into `configuration.nix` and reduce `default.nix` to:

  ```nix
  { ... }:
  {
    imports = [ ./configuration.nix ];
  }
  ```

- [ ] **Step 4: Make the flake consume the directory entry point**

  Change `nix/flakes/darwin.nix` from `../hosts/darwin/default.nix` to `../hosts/darwin` and preserve all nix-darwin, Homebrew, overlay, and Home Manager inputs.

- [ ] **Step 5: Run the host tests and verify GREEN**

  Run the focused Nix-unit build and evaluate the Darwin configuration with fixed `DOTFILES_USER` and `DOTFILES_HOME` values. Confirm that effective Homebrew, launchd, system defaults, and Home Manager options remain available.

- [ ] **Step 6: Commit the Darwin host split**

  ```bash
  git add nix/hosts/darwin nix/flakes/darwin.nix nix/tests/hosts nix/flakes/tests.nix
  git commit -m "refactor(nix): split Darwin host entry point"
  ```

### Task 4: Move Nix configuration assertions from Bats to Nix

**Files:**

- Modify or delete: `tests/bash/home_layout.bats`
- Modify: `tests/bash/flake_outputs.bats`
- Modify: `tests/bash/macos_config.bats`
- Modify: `nix/tests/home/composition.nix`
- Modify: `nix/tests/home/README.md`
- Test: retained Bats contract files and Nix checks

**Interfaces:**

- Nix configuration assertions have one Nix-native owner.
- Retained Bats tests continue to use the repository's existing `task test:bash`/CI contract route.

- [ ] **Step 1: Classify current Bats tests**

  Move assertions about Home Manager options, package lists, session variables, module imports, flake output selection, and NixOS/WSL Home Manager wiring into Nix tests. Keep shell ordering, installer failures, stubbed external commands, and runtime acceptance in Bats.

- [ ] **Step 2: Replace structural Bats coverage**

  Remove the duplicate `home_layout.bats` coverage after `platform-boundary.nix` and `import-boundary.nix` pass. Remove only Nix configuration cases from `flake_outputs.bats` and `macos_config.bats`; retain non-Nix shell/runtime contracts.

- [ ] **Step 3: Update test ownership documentation**

  Rewrite `nix/tests/home/README.md`, `nix/README.md`, and `nix/home/README.md` so the exact Nix command is authoritative for Nix configuration. Document Bats only for its remaining contract scope.

- [ ] **Step 4: Add an ownership regression check**

  Add a deterministic Nix or repository contract assertion that rejects reintroducing Home Manager-only test files under `tests/bash/` without an explicit runtime/installer reason.

- [ ] **Step 5: Commit the test migration**

  ```bash
  git add nix/tests tests/bash nix/README.md nix/home/README.md
  git commit -m "test(nix): make Nix authoritative for Nix configuration"
  ```

### Task 5: Update contributor and CI ownership contracts

**Files:**

- Modify: `AGENTS.md` if required
- Modify: `.github/workflows/ci-bootstrap.yml` if required
- Modify: `.github/workflows/ci-contract.yml` if required
- Modify: `tests/python/test_detect_ci_changes.py` and/or related contracts if routing changes
- Modify: `nix/tests/home/README.md`
- Test: repository routing and documentation checks

**Interfaces:**

- CI runs Nix-native checks for Nix changes and Bats only for retained shell/runtime contracts.
- No required check is silently removed or left pending by path routing.

- [ ] **Step 1: Trace path routing**

  Update the authoritative path map and workflow comments for `nix/home/**`, `nix/tests/**`, and removed/retained Bats files. Ensure Nix changes select the Nix check.

- [ ] **Step 2: Update contributor instructions**

  Add a direct rule: when the subject under test is a Nix expression or Home Manager option, add the test under `nix/tests/`; use Bats only for shell/installer/external process behavior.

- [ ] **Step 3: Run routing and documentation tests**

  Run the focused Python/routing checks, Nix checks, and `git diff --check`.

- [ ] **Step 4: Commit the ownership contract**

  ```bash
  git add AGENTS.md .github tests/python nix/tests/home/README.md
  git commit -m "docs(ci): enforce Nix test ownership"
  ```

### Task 6: Full verification and publication

**Files:**

- Review: all changed files and final diff
- Test: Nix checks, format, lint, relevant retained Bats/contracts

- [ ] **Step 1: Run formatting and repository checks**

  Run `nix fmt -- --fail-on-change`, `nix flake check --all-systems --no-build --no-write-lock-file`, relevant Python/routing tests, and the retained Bats contract subset. Investigate every failure before continuing.

- [ ] **Step 2: Review the final diff**

  Confirm no unrelated files, secrets, activation commands, or primary-worktree changes are included. Confirm all new tests are Nix-native for Nix configuration behavior.

- [ ] **Step 3: Push and create the PR**

  Push `codex/issue-585-nix-test-authority`, create a PR against `main`, and link #585 and #587–#591.

- [ ] **Step 4: Verify hosted Actions and review state**

  Wait for required checks, inspect failures with their logs, resolve review threads, and confirm the repository's allowed merge method.

- [ ] **Step 5: Merge and verify**

  Merge only after all required checks and review threads are complete. Verify the merged PR, merge commit, and remote `main` state. Preserve the original dirty primary worktree and do not remove unrelated worktrees.
