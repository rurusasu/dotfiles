# Hermes installer integration Task I4 review-gap report

## Scope

- Changed only `scripts/powershell/tests/handlers/Handler.HermesAgent.Tests.ps1`.
- Added one shared ordered event log covering Compose validation, image build,
  bootstrap, and service recreation.
- Added exception boundaries for validation, build, bootstrap, and startup.
- Added a fresh-`pwsh` loader simulation using the real setup libraries and all
  real handlers.
- Added migration exit-code 5 coverage that permits only runtime directory
  preparation before failure.

## Review-gap coverage

- Success requires the exact event sequence `config -> build -> bootstrap -> up`.
- Every exception returns failure and excludes all later phases; bootstrap
  exceptions explicitly exclude `up`.
- The loader simulation follows the `install.admin.ps1` library order available
  on macOS, loads exactly one Phase 2 non-admin Hermes handler, resolves the
  actual `Invoke-HermesBootstrap` function, and confirms both guarded Add-Type
  classes load without conflict.
- Migration exit code 5 is preserved in the handler result, does not run `up`,
  and creates no host files. Only the data directory, `.xurl`, and browser data
  directory are prepared.

## Verification

- Handler Pester: 16 passed, 0 failed.
- HermesBootstrap Pester: 16 passed, 0 failed.
- Handler test parser: passed.
- Handler test PSScriptAnalyzer 1.22.0: no Error/Warning findings.
- Repository PSScriptAnalyzer gate: 29 passed, 0 failed.
- `git diff --check`: passed before commit.
