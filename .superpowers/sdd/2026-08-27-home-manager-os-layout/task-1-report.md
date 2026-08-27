# Task 1 Report: Canonical OS module contract tests

## Status

Completed. Task 1 adds only the planned contract tests and intentionally leaves
the focused Bats suite red until Tasks 2 and 3 create and wire the canonical
Home Manager OS modules.

## Files changed

- `tests/bash/home_layout.bats` — added canonical flat-layout and
  `common.nix` import-direction assertions.
- `tests/bash/linux_config.bats` — changed Linux and WSL alias contracts to
  read `nix/home/linux.nix` and `nix/home/wsl.nix`.
- `tests/bash/macos_config.bats` — added the Darwin canonical module wiring
  contract.
- `tests/bash/flake_outputs.bats` — added NixOS and standalone Home Manager
  OS-module selection contracts.
- `scripts/powershell/tests/PackageCatalog.Tests.ps1` — changed the Linux and
  WSL alias contract inputs to the canonical flat paths.

## Tests and results

Ran:

```bash
bats tests/bash/home_layout.bats tests/bash/linux_config.bats tests/bash/macos_config.bats tests/bash/flake_outputs.bats
```

Result: expected failure (6 failing, 38 passing, exit 1).

The failures are limited to the intentionally absent canonical artifacts and
wiring: `nix/home/README.md`, `nix/home/darwin.nix`, `nix/home/linux.nix`,
`nix/home/wsl.nix`, Darwin's canonical import, and canonical flake module
paths. This is the planned red state for Tasks 2 and 3.

## Concerns

- The focused command does not invoke PowerShell directly. The commit hook's
  PowerShell tests passed after the focused Bats result was recorded.
- Existing dirty `flake.lock` and untracked
  `.codex/hooks/claude_permission_policy.py` were preserved and must not be
  included in this task's commit.
