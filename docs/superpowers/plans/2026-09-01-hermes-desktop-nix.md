# Hermes Desktop Nix Integration Implementation Plan

> **Superseded:** This plan was replaced on 2026-09-03 by
> [#554](https://github.com/rurusasu/dotfiles/issues/554), which manages Hermes
> Desktop through the official Homebrew Cask. See the
> [current operations guide](../../hermes-agent/desktop.md).

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add the official Hermes Desktop Nix output to the `WithHermes` macOS
profile while keeping the Agent and Web Dashboard in the existing Compose stack.

**Architecture:** The root flake pins `NousResearch/hermes-agent` and passes its
`packages.<system>.desktop` output into the package catalog. `hermes-desktop` is
a Darwin command package enabled by `WithHermes`; the existing `hermes` container
continues to own the gateway and dashboard at `127.0.0.1:9119`.

**Tech Stack:** Nix flakes, nix-darwin, Home Manager, Docker Compose, Bash/Bats,
Python unittest, go-task, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-01-hermes-desktop-nix-design.md`

## Global Constraints

- Work only in `/Users/ktome1995/Program/dotfiles/.worktrees/hermes-desktop-nix`.
- Preserve all unrelated changes in the primary checkout.
- Keep Hermes credentials, sessions, models, and runtime state outside `/nix/store`.
- Do not add Electron or a GUI runtime to `docker/hermes-agent`.
- Keep `--with-hermes` as the single opt-in switch for Docker Hermes and Desktop.
- Record the existing `bootstrap-nixos-vm` baseline evaluation failure; do not fix
  unrelated NixOS test code in this change.

## Task 1: Pin the upstream Hermes flake and add the catalog contract

**Files:** `flake.nix`, `flake.lock`, `nix/packages/sets.nix`,
`nix/packages/darwin-provider-candidates.nix`,
`tests/bash/package_catalog.bats`, `tests/python/test_update_darwin_packages.py`

- [ ] Add a failing contract test for the `hermes-desktop` candidate, its
      `WithHermes` feature, and Darwin-only provider metadata.
- [ ] Run the focused test and confirm it fails because the catalog entry/input
      does not exist.
- [ ] Add the official `hermes-agent` flake input, following the repository's
      nixpkgs where compatible, and update `flake.lock` with Nix.
- [ ] Add an optional `hermesDesktopPackage` argument to `sets.nix`; resolve
      `hermes-desktop` from the supplied upstream package on Darwin only.
- [ ] Add provider metadata and ensure the package is a Darwin Nix/Home Manager
      package enabled only by `WithHermes`.
- [ ] Run the focused catalog tests and `nix eval` checks for default/WithHermes
      resolution.
- [ ] Commit the flake/catalog foundation.

## Task 2: Wire the package through nix-darwin and document the split

**Files:** `nix/hosts/darwin/default.nix`, `nix/flakes/packages.nix`,
`README.md`, `scripts/sh/install-macos.sh`, `docs/hermes-agent/desktop.md`,
`tests/bash/install_macos.bats`, `tests/python/test_ci_workflow_routing.py`

- [ ] Add a failing assertion that the Darwin host passes the upstream Desktop
      output and that `--with-hermes` describes the native GUI plus Compose backend.
- [ ] Pass the package from flake inputs into nix-darwin's catalog and keep
      standalone package outputs consistent.
- [ ] Update installer help and user documentation with the host/container split,
      Dashboard URL, authentication requirement, and runtime-state boundary.
- [ ] Add the Hermes Desktop documentation path to the existing CI routing.
- [ ] Run focused Bash/Python contract tests and Nix evaluation.
- [ ] Commit the host wiring and documentation.

## Task 3: Verify, review, and deliver through GitHub

**Files:** only files changed by Tasks 1-2 unless CI exposes a necessary contract.

- [ ] Run `nix fmt`, focused Bats/Python tests, `docker compose ... config --quiet`,
      and relevant package-provider checks.
- [ ] Run `nix flake check --no-build --impure --all-systems`, record only the
      pre-existing bootstrap VM assertion failure if it remains.
- [ ] Review the final diff, commit, and push the feature branch.
- [ ] Create a PR closing issue #538, inspect the repository ruleset and review
      threads, and wait for all required Actions checks.
- [ ] Address Critical/Important review or CI failures, rerun verification, and
      repeat until the PR is mergeable.
- [ ] Merge with the repository-allowed method and verify the merged PR and issue.
