# Cloud Task 2 Report: Document the cloud-only guarantee boundary

## Status

Implemented the hosted-only CI documentation boundary.

## Implementation

- Replaced the README CI guarantee with the GitHub-hosted-only model and the local acceptance boundary for Windows/macOS runtime behavior.
- Replaced the architecture workflow row and merge policy with the hosted Windows/macOS/Linux workflow and Linux runtime E2E boundary.
- Added the PowerShell testing CI strategy for hosted contracts, Linux runtime coverage, and the `Protected Bootstrap E2E` aggregate.
- Marked the old Windows/macOS self-hosted design sections as superseded by the 2026-07-19 cloud-only CI design.
- Deleted the obsolete self-hosted runner operations guide.
- Updated Bats documentation contract tests to require hosted CI references and forbid obsolete runner labels, Environment names, and workflow names.

## Files

- `README.md`
- `docs/architecture.md`
- `docs/scripts/powershell/testing.md`
- `docs/superpowers/specs/2026-07-17-cross-platform-bootstrap-design.md`
- `docs/ci/self-hosted-bootstrap-runners.md` (deleted)
- `tests/bash/bootstrap_docs.bats`

## RED/GREEN evidence

### RED

After updating `tests/bash/bootstrap_docs.bats`, `bats tests/bash/bootstrap_docs.bats` failed as intended:

- `README documents all bootstrap entrypoints and reruns` failed because `README.md` did not contain `GitHub-hosted`.
- `operational docs require only hosted bootstrap CI` failed because `docs/ci/self-hosted-bootstrap-runners.md` still existed.

### GREEN

After applying the specified documentation replacements and deleting the runner guide:

```text
nix fmt
# formatted 0 files (0 changed)

bats tests/bash/bootstrap_docs.bats
1..4
ok 1 README documents all bootstrap entrypoints and reruns
ok 2 operational docs require only hosted bootstrap CI
ok 3 architecture documents the four declarative layers
ok 4 package and PowerShell docs describe generated coverage and acceptance

git diff --check
# exit 0
```

## Self-review

- Confirmed Task 1's `.github/workflows/ci-bootstrap-e2e-hosted.yml` remains unchanged.
- Confirmed the three operational documents contain no `dotfiles-e2e`, `destructive-e2e`, or `ci-bootstrap-e2e-self-hosted.yml` references.
- Confirmed `README.md` no longer links to the deleted runner guide.
- Confirmed the referenced cloud-only design file exists.
- Confirmed the final diff contains only the six owned documentation/test files plus this required report.

## Concerns

`nix fmt` exits successfully but emits an expected walker warning while the intentionally deleted runner-guide path remains in Git's worktree state. No formatting changes were made in the final verification run.
