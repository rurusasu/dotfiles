# Package Test Boundaries Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move pure package/catalog assertions to the authoritative nix-unit suite and add explicit build checks for repository-owned custom package derivations while preserving runtime/artifact coverage.

**Architecture:** Keep three test layers. Nix-unit owns evaluated package/provider/configuration semantics; an aggregate Nix derivation check realizes explicit custom package derivations; Bats and existing platform suites own runtime, artifact, external-command, and host-specific behavior. CI and ownership checks will enforce these boundaries.

**Tech Stack:** Nix, nix-unit, flake-parts, Nix derivations, Bats, Taskfile, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-26-package-test-boundaries-design.md`

## Global Constraints

- Pure package/provider/selection/source-shape assertions must live under `nix/tests/` and use nix-unit attrsets.
- Do not add Nix-evaluating Bats tests; retain only runtime/artifact contracts in `tests/bash/`.
- Custom package build checks must be explicit and platform-guarded; do not build every upstream nixpkgs package selected by the catalog.
- Do not perform privileged activation or live service startup in package build checks.
- Verify with the focused nix-unit build, custom package build check, relevant Bats tests, and `nix flake check --all-systems --no-write-lock-file` where supported.

## Review Focus

- Package catalog cases that accidentally retain `nix eval` in Bats — ownership test must fail before the migration and pass after it.
- Platform-specific custom derivations — unsupported systems must not be forced to build a package.
- Custom package build coverage — the check must realize `installPhase`, not merely evaluate package metadata.
- Source-shape ports — preserve semantic assertions and avoid weakening them to presence-only checks without an explicit reason.
- Runtime/artifact contracts — the five non-pure package tests must remain in the runtime suite and continue to run.

### Task 1: Migrate pure package catalog assertions to nix-unit

**Files:**

- Create: `nix/tests/packages/catalog.nix`
- Modify: `nix/flakes/tests.nix`
- Modify: `nix/tests/ownership.nix`
- Modify: `tests/bash/package_catalog.bats`
- Modify: `nix/tests/home/README.md`

**Interfaces:**

- Consumes the existing `sets.nix` package/provider outputs and the test inputs already passed to `nix/flakes/tests.nix`.
- Produces a registered nix-unit attrset containing the migrated pure catalog tests and an ownership assertion that only the intended Bats files contain `nix eval`.

- [ ] **Step 1: Write the failing ownership test**

  Change the expected Nix-evaluating Bats owners so `package_catalog.bats` is no longer accepted, while leaving its current Nix-eval cases in place.

- [ ] **Step 2: Run the focused nix-unit check and verify it fails**

  Run:

  ```bash
  nix build .#checks.$(nix eval --raw --impure --expr 'builtins.currentSystem').nix-unit --no-link --no-write-lock-file
  ```

  Expected: the ownership assertion fails because `tests/bash/package_catalog.bats` still contains Nix evaluation commands.

- [ ] **Step 3: Add `nix/tests/packages/catalog.nix` and port the pure cases**

  Port the 41 catalog/provider/selection/source-shape cases into focused
  `{ expr, expected }` tests. Use shared local fixtures for the package sets
  and catalog overrides so the tests evaluate the same public outputs rather
  than invoking shell commands or parsing JSON through Bats.

- [ ] **Step 4: Register the new test attrset**

  Import `../tests/packages/catalog.nix` from `nix/flakes/tests.nix`, passing
  `inputs` where needed, and preserve unique `test...` attribute names.

- [ ] **Step 5: Remove the migrated Bats cases**

  Delete only the pure Nix/catalog cases from `tests/bash/package_catalog.bats`.
  Keep the five runtime/artifact cases: pnpm global behavior, generated
  manifests, signed Raycast/Discord artifacts, and the remaining artifact
  contract.

- [ ] **Step 6: Run the focused nix-unit check and the package runtime tests**

  Expected: the new nix-unit tests and updated ownership assertion pass, and
  the remaining `package_catalog.bats` runtime/artifact tests pass without
  any Nix-evaluating Bats owner.

- [ ] **Step 7: Update ownership documentation**

  Update `nix/tests/home/README.md` to remove the migrated cases from the
  temporary Nix/catalog exception list and document the five retained runtime
  contracts.

- [ ] **Step 8: Commit the migration**

  ```bash
  task commit -- "test: move package catalog assertions to nix-unit"
  ```

### Task 2: Add explicit custom package build checks

**Files:**

- Create: `nix/tests/packages/custom-builds.nix`
- Modify: `nix/flakes/packages.nix`
- Modify: `taskfiles/test/taskfile.yml`
- Test: `nix/tests/packages/custom-builds.nix` through the focused flake check

**Interfaces:**

- Consumes explicit custom derivations for `chatgpt`, `dia-browser`,
  `hammerspoon`, `neovim`, and `orca-editor`, with platform guards matching
  their `meta.platforms` and catalog providers.
- Produces `checks.custom-package-builds`, an aggregate derivation that
  realizes each supported custom package and therefore executes its build and
  install phases.

- [ ] **Step 1: Write the failing build-check invocation**

  Run the intended command before adding the check:

  ```bash
  nix build .#checks.$(nix eval --raw --impure --expr 'builtins.currentSystem').custom-package-builds --no-link --no-write-lock-file
  ```

  Expected: failure because the check output does not yet exist.

- [ ] **Step 2: Implement the explicit platform-aware package map**

  Add a helper that returns only supported custom derivations for the current
  system. Use the repository package definitions rather than rebuilding every
  package in `sets.nix`; do not include upstream-only providers.

- [ ] **Step 3: Implement the aggregate derivation**

  Use a small `linkFarm`-style derivation whose inputs are the explicit custom
  package derivations. The check must create a non-empty output and must not
  hide build failures behind evaluation-only assertions.

- [ ] **Step 4: Wire the check into flake outputs**

  Add `custom-package-builds` to `perSystem.checks` in `nix/flakes/packages.nix`.
  Keep existing package outputs and `neovim-native` behavior unchanged.

- [ ] **Step 5: Add the focused Taskfile command**

  Extend `task test:nix` with the aggregate custom-package build check after
  the nix-unit check and before the runtime-oriented checks.

- [ ] **Step 6: Run the build check and verify it passes**

  Run the command from Step 1. Expected: Nix realizes all custom derivations
  supported by the current system and returns exit 0.

- [ ] **Step 7: Commit the build checks**

  ```bash
  task commit -- "test: build custom package derivations"
  ```

### Task 3: Align CI routing and test documentation

**Files:**

- Modify: `.github/workflows/ci-consistency.yml` or the repository's package-check workflow selected by the existing routing manifest
- Modify: `.github/workflows/ci-bootstrap.yml` if the Nix check matrix requires the new output
- Modify: `tests/bash/ci_routing.bats` if path routing assertions change
- Modify: `nix/README.md`, `nix/tests/home/README.md`, and task descriptions as needed

**Interfaces:**

- Consumes the `nix-unit` and `custom-package-builds` outputs from Tasks 1 and 2.
- Produces CI and local commands that run the same authoritative checks without reintroducing duplicate Bats assertions.

- [ ] **Step 1: Write the failing routing/documentation contract**

  Add or update a routing assertion for package test changes that requires the
  Nix-native checks and the retained runtime/artifact suite.

- [ ] **Step 2: Run the focused routing test and verify it fails**

  Run the relevant `bats tests/bash/ci_routing.bats` filter. Expected: failure
  because the new check target is not yet represented in routing/documentation.

- [ ] **Step 3: Update CI and task routing**

  Ensure package-related changes run the focused nix-unit build, aggregate
  custom-package build, and retained runtime/artifact tests. Do not make
  unrelated platform jobs depend on unsupported custom derivations.

- [ ] **Step 4: Update the written test-boundary guidance**

  Document the three layers, exact commands, and the five retained runtime
  contracts. Remove stale claims that package catalog assertions belong in
  Bats.

- [ ] **Step 5: Run routing and documentation tests**

  Expected: routing tests pass and all referenced commands point to existing
  outputs/files.

- [ ] **Step 6: Commit the CI and documentation alignment**

  ```bash
  task commit -- "ci: align package test boundaries"
  ```

### Task 4: Whole-branch verification and review

**Files:**

- Verify all files changed by Tasks 1-3.

- [ ] **Step 1: Run focused checks**

  Run the current-system nix-unit check, custom-package build check, retained
  package runtime Bats tests, routing tests, and `git diff --check`.

- [ ] **Step 2: Run the authoritative broader checks**

  Run `nix flake check --all-systems --no-write-lock-file` and the relevant
  `task test:bash`/CI contract suites. Record any environment-only failures
  separately from code failures.

- [ ] **Step 3: Inspect final diff and test ownership**

  Confirm the pure assertions exist only in Nix tests, runtime contracts remain
  in Bats, custom build checks are platform-aware, and no unrelated files were
  changed.

- [ ] **Step 4: Request whole-branch review**

  Review against the spec, this plan's Review Focus, and the test output before
  reporting completion or integration readiness.
