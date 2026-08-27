# Task 5 Report: CI routing and path-based contracts

## Scope completed

- Replaced the obsolete `nix/home/linux/**`, `nix/home/users/**`, and
  `nix/home/wsl/**` routing patterns with the flat canonical OS module paths.
- Added explicit routing for `nix/home/darwin.nix` and `nix/home/README.md`.
  Linux and WSL modules continue to select only their respective platform
  checks.
- Updated Bash and Python routing contracts for Linux, WSL, Darwin, and the
  Home Manager layout README.
- Updated the Darwin rebuild-alias assertion to read `nix/home/darwin.nix`.
- Corrected the stale WSL module reference in `chezmoi/shells/AGENTS.md`.
- Did not edit `scripts/powershell/tests/PackageCatalog.Tests.ps1`: its
  canonical `nix/home/wsl.nix` and `nix/home/linux.nix` assertions already
  existed, and its unrelated dirty `-EQ` edits were preserved.

## Validation

- The required obsolete-reference `rg` command exited 0 with no output.
- `bats tests/bash/ci_routing.bats` exited 0: 18/18 passed.
- `python3 -m unittest tests.python.test_detect_ci_changes -v` exited 0: 23/23
  passed.
- The required 7-suite Bats command exited 0: 81/81 passed. Bats emitted the
  existing `BW02` minimum-version warning from `flake_outputs.bats:59`.
- The full PowerShell command on macOS exited 1: 913 passed, 205 failed, and
  5 skipped. The plan requires this suite to exit 0 on a Windows runner;
  macOS acceptance is limited to the focused PackageCatalog suite below.
- The focused PackageCatalog Pester command exited 0: 47 passed, 0 failed,
  0 skipped.

## Concerns

The 205 macOS full-suite failures are pre-existing environment limitations,
not demonstrated CI-routing regressions:

- Windows-host-only tests require Windows facilities such as `C:` / `D:`
  drives, elevation, registry state, or WSL.
- Windows executable and fixture tests require Windows binaries, paths, or
  fixtures that are unavailable on macOS.
- Test-harness portability failures arise from PowerShell/Pester assumptions
  that do not hold on macOS.

The focused Task 5 PowerShell package-catalog contract passes on macOS. Full
Pester green status remains a Windows-runner requirement.
