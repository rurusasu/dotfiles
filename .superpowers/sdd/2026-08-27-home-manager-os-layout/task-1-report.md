# Task 1 Report: Canonical OS module contract tests

## Status

Completed. Task 1 adds only the planned contract tests and intentionally leaves
the focused Bats suite red until Tasks 2 and 3 create and wire the canonical
Home Manager OS modules.

## Files changed

- `tests/bash/home_layout.bats` — added canonical flat-layout and one-way
  import-direction assertions, including rejection of OS-module imports from
  `common.nix`.
- `tests/bash/linux_config.bats` — changed Linux and WSL alias contracts to
  read `nix/home/linux.nix` and `nix/home/wsl.nix`.
- `tests/bash/macos_config.bats` — added the Darwin canonical module wiring
  contract.
- `tests/bash/flake_outputs.bats` — added NixOS and standalone Home Manager
  OS-module selection contracts plus selected-user Home Manager evaluation.
- `scripts/powershell/tests/PackageCatalog.Tests.ps1` — changed the Linux and
  WSL alias contract inputs to the canonical flat paths.

## Tests and results

Ran:

```bash
bats tests/bash/home_layout.bats tests/bash/linux_config.bats tests/bash/macos_config.bats tests/bash/flake_outputs.bats
```

Result: expected failure (7 failing, 39 passing, exit 1).

The failures are limited to the intentionally absent canonical artifacts and
wiring: `nix/home/README.md`, `nix/home/darwin.nix`, `nix/home/linux.nix`,
`nix/home/wsl.nix`, Darwin's canonical import, canonical flake module paths,
and selected-user NixOS module application. This is the planned red state for
Tasks 2 and 3.

Ran:

```bash
pwsh -NoProfile -Command 'Invoke-Pester -Path scripts/powershell/tests/PackageCatalog.Tests.ps1 -CI -Output Detailed'
```

Result: expected failure (46 passing, 1 failing, exit 1). The failing test is
`should update WSL inputs and route native NixOS through the hardware-safe
installer`; its canonical Linux and WSL module inputs do not exist before Task
2.

## Concerns

- The focused Bats and direct PowerShell suites are intentionally red until
  Tasks 2 and 3 create and wire the canonical modules. The PowerShell result
  above supersedes the prior incorrect commit-hook pass claim.
- Existing dirty `flake.lock` and untracked
  `.codex/hooks/claude_permission_policy.py` were preserved and must not be
  included in this task's commit.
