# Cloud Task 1 Report

## Implementation

- Replaced the self-hosted bootstrap workflow with `.github/workflows/ci-bootstrap-e2e-hosted.yml`.
- Added hosted Windows, macOS, and aggregate Ubuntu contract jobs with the required names, runner labels, timeouts, permissions, pinned actions, contract commands, and attestation artifacts.
- Removed `.github/workflows/ci-bootstrap-e2e-self-hosted.yml`.
- Replaced the three self-hosted workflow/security expectation tests in `scripts/powershell/tests/CiWorkflow.Tests.ps1` with the two hosted-runner contract tests from the task brief.
- Linux runtime E2E remains represented by the existing Linux workflow; hosted Windows/macOS attestations explicitly mark runtime as not applicable.

## Files changed

- `.github/workflows/ci-bootstrap-e2e-hosted.yml` (created)
- `.github/workflows/ci-bootstrap-e2e-self-hosted.yml` (deleted)
- `scripts/powershell/tests/CiWorkflow.Tests.ps1` (modified)
- `.superpowers/sdd/cloud-task-1-report.md` (created)

## Tests and results

- `pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1 -Path scripts/powershell/tests/CiWorkflow.Tests.ps1 -MinimumCoverage 0`
  - PASS: 24 passed, 0 failed, 0 skipped.
- `nix fmt`
  - PASS: formatter exited 0.
- `git diff --check`
  - PASS: exited 0 with no whitespace errors.
- PowerShell file encoding review
  - CRLF line endings and UTF-8 without BOM confirmed.

## RED evidence

After replacing the three old assertions with the two required hosted-runner tests, the focused test failed as expected: 22 passed and 2 failed. The first failure reported that the self-hosted workflow still existed; the second reported that the hosted workflow did not exist.

## GREEN evidence

After deleting the self-hosted workflow and adding the hosted workflow, the same focused command passed with 24 passed, 0 failed, 0 skipped.

## Self-review

- The hosted workflow uses `windows-2025`, `macos-15`, and `ubuntu-24.04`; no self-hosted labels, destructive environment, or fork restriction remain.
- Windows invokes `Invoke-Tests.ps1 -MinimumCoverage 0 -IncludeIntegration`; macOS runs `bats tests/bash`, the macOS declarative build, and provider coverage build.
- Windows and macOS artifact names include run ID and attempt and include the required attestation fields; the aggregate job requires both contract jobs to succeed.
- Checkout, Nix installation, and artifact upload actions remain pinned to the repository-specified SHAs.
- Changes are limited to the requested workflow/test ownership plus this requested report.

## Concerns

- The hosted Windows/macOS jobs intentionally provide bootstrap contracts and non-runtime attestations only; they do not replace destructive runtime acceptance. Runtime E2E remains delegated to the existing Linux workflow as specified by the task.
- The workflow was not executed on actual GitHub-hosted Windows/macOS runners in this environment; local verification is limited to contract tests, formatting, diff checks, and encoding inspection.
