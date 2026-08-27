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
- The full PowerShell command was non-zero on macOS: observed failures depend
  on unavailable Windows `C:` / `D:` drives (`ConfigureLifelogRoot`,
  `Install.Admin`, `Install.Tests`, and `Install.User`). The complete Pester
  summary could not be captured because the command exceeded the terminal's
  30-second output window.
- The focused PackageCatalog Pester command exited 0: 47 passed, 0 failed,
  0 skipped.

## Concerns

The required all-PowerShell suite is not green in this macOS environment due
to pre-existing Windows-drive assumptions outside Task 5. The Task 5-relevant
PowerShell package-catalog contract passes.
