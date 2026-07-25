# Hermes Distribution Validation Design

## Status And Scope

Approved design for repository-local validation, GitHub Actions fallback, and
agent-driven remediation for the remote-authoritative `rurusasu/hermes-home`
root repository. The same contract can apply to another source repository only
when that repository explicitly opts in and retains the complete validation
tooling bundle defined below.

This document is not the current contract for named-profile exact mirrors.
Those repositories intentionally delete repository-local workflows,
pre-commit configuration, validators, tests, README files, and other paths
outside the declarative profile allowlist. For named mirrors, the
[Local-Authoritative Profile Sync Design](profile-local-authoritative-sync-design.md)
supersedes the former scope of this document.

## Problem

In-scope source repositories need hosted pull-request checks, but
GitHub-hosted Actions for private repositories are metered. Exhausted minutes
or a budget configured to stop usage can prevent a workflow from starting even
when the distribution is valid.

Treating GitHub Actions as the only gate creates two failures:

- a valid change cannot progress when hosted execution is unavailable;
- an agent cannot reliably distinguish a code failure from billing,
  environment, stale-evidence, or workflow-trigger failures.

Local checks also need a stable machine-readable result so an agent can fix a
specific failure and the controller can independently verify the repair.

## Goals

- Give each explicitly in-scope source repository a self-contained local guard.
- Run the same full validation contract locally and in GitHub Actions.
- Minimize hosted runner usage without weakening pull-request validation.
- Distinguish code failures, local prerequisite failures, stale evidence,
  unknown remote failures, and explicit GitHub billing blocks.
- Allow automatic merge from local evidence only for an explicitly identified
  billing block.
- Define when an agent repair succeeded, failed, or requires human/context
  intervention.
- Keep repository tooling and CI metadata outside root-owned runtime paths.

## Non-Goals

- Applying a repository-local validation bundle to named-profile exact mirrors.
- Preserving allowlist-external tooling in a named-profile remote tree.
- Replacing GitHub Actions when hosted execution is available.
- Automatically merging when no workflow run appears for an unknown reason.
- Allowing agents to bypass failed local validation with `--no-verify`.
- Sharing a private remote pre-commit plugin that introduces another
  authentication and availability dependency.
- Copying generated validation reports into Git history.

## Repository Contract

The current repository contract contains:

| Repository             | Distribution manifest    | Runtime boundary |
| ---------------------- | ------------------------ | ---------------- |
| `rurusasu/hermes-home` | `root-distribution.yaml` | `/opt/data` root |

No named-profile repository is part of this table. A new source repository is
in scope only after an explicit contract change names it, defines its
distribution manifest and boundary checks, and requires all of these paths:

```text
.github/workflows/distribution.yml
.pre-commit-config.yaml
scripts/validate_distribution.py
.gitignore
```

A distribution declaration, profile manifest entry, or remote URL alone does
not opt a repository into this contract.

The Python driver contains no YAML implementation of its own. It invokes the
pinned Hermes image for distribution parsing and installation behavior, and a
pinned Gitleaks image for secret scanning. Keeping the driver
repository-local allows a fresh clone to validate without access to another
private repository. The small amount of duplicated orchestration is preferable
to a networked pre-commit dependency.

For `hermes-home`, the driver reads identity and owned paths from
`root-distribution.yaml`. An explicitly added source repository must declare
its own manifest and repository-specific assertions as data near the top of
the driver rather than introduce divergent control flow.

## Validation Levels

The command interface is:

```text
python3 scripts/validate_distribution.py fast [--json] [--output PATH]
python3 scripts/validate_distribution.py full [--json] [--output PATH]
```

`fast` runs:

- `manifest-schema`;
- `owned-paths`;
- `config-contract`;
- `repository-policy`;
- `secret-patterns`.

`secret-patterns` asks Git for tracked files plus non-ignored untracked files
(`git ls-files --cached --others --exclude-standard -z`) and scans those
regular files only. It separately asks Git for worktree deletions
(`git ls-files --deleted -z`) and excludes those absent paths because they
cannot enter the next source commit; malformed or failed deletion enumeration
remains a fail-closed error. Ignored runtime material such as `.env`, auth
state, memories, and caches is not part of the source-distribution guard.
Failure to enumerate or read any other in-scope file fails the check closed
with a redacted count.

`full` runs every fast check plus:

- `hermes-parser`;
- `root-boundary` for `hermes-home`, or the boundary probe explicitly declared
  by another in-scope source repository;
- `gitleaks`.

The root-boundary probe asserts that installation changes only paths declared
by `root-distribution.yaml`. There is no implicit named-profile boundary probe
in this contract.

Exit codes are stable:

| Code | Meaning                    | Agent action                         |
| ---- | -------------------------- | ------------------------------------ |
| `0`  | all requested checks pass  | continue                             |
| `1`  | validation failure         | dispatch a fix agent                 |
| `2`  | prerequisite unavailable   | report `ENV_BLOCKED`; do not rewrite |
| `3`  | validator internal failure | report `INTERNAL_ERROR`; stop        |

Human output names failed check IDs without exposing file contents that may
contain secrets. `--json` emits one JSON document; `--output` writes it through
an atomic rename under a caller-selected ignored path.

## Result Schema

```json
{
  "schema_version": 1,
  "validator_version": "1.0.0",
  "repository": "hermes-home",
  "head_sha": "0123456789abcdef",
  "level": "full",
  "status": "pass",
  "exit_code": 0,
  "checks": [
    {
      "id": "root-boundary",
      "status": "pass",
      "message": "Hermes root ownership contract accepted"
    }
  ]
}
```

Allowed check statuses are `pass`, `fail`, and `blocked`. Messages are
redacted, single-line summaries. A result is valid only when `head_sha` equals
both local `HEAD` and the pull request's current `headRefOid`.

Generated reports live under `.hermes-validation/`, which every in-scope
repository ignores.

## Local Git Guards

The retained `.pre-commit-config.yaml` defines repository-local hooks:

- pre-commit stage: `validate_distribution.py fast`;
- pre-push stage: `validate_distribution.py full`.

Repository setup installs both hooks:

```text
pre-commit install --hook-type pre-commit --hook-type pre-push
```

The fast hook deliberately fails with prerequisite exit code `2` when Docker
or the pinned Hermes image is unavailable. It does not silently downgrade YAML
contract validation. Repository setup therefore pulls the pinned images before
installing hooks; the hosted workflow performs the same explicit pulls.

Agents must also invoke both stages explicitly before reporting completion.
The controller does not trust hook execution because Git hooks can be absent or
bypassed; it reruns full validation independently for the exact commit.

## GitHub Actions Guard

Each in-scope repository has one `distribution` workflow with one Linux job. It
runs on `pull_request` and manual dispatch, not on both pull request and branch
push. It uses:

- one job and no matrix;
- `concurrency` keyed by workflow and pull request with
  `cancel-in-progress: true`;
- a ten-minute timeout;
- pinned action commit SHAs;
- the same `validate_distribution.py full --json` command;
- no artifact upload or cache unless later measurements justify them.

The JSON summary is written to the job log and GitHub step summary. This keeps
hosted usage small and ensures that local and hosted checks do not encode
different acceptance rules.

## Remote State Classification

The controller combines the local full result, pull-request head SHA, workflow
definition/state, workflow run, check suite/run output, and billing evidence.
It produces exactly one state:

| State                 | Meaning                                                | Merge |
| --------------------- | ------------------------------------------------------ | ----- |
| `PASS_REMOTE`         | local full pass and current-head workflow success      | yes   |
| `PASS_LOCAL_FALLBACK` | local full pass and explicit current-head billing stop | yes   |
| `FAIL_VALIDATION`     | local or hosted validator reports failed check IDs     | no    |
| `FIX_FAILED`          | automated repair limit reached with checks failing     | no    |
| `ENV_BLOCKED`         | Docker, image, pre-commit, or auth prerequisite absent | no    |
| `REMOTE_PENDING`      | current-head workflow is queued or running             | no    |
| `REMOTE_UNKNOWN`      | no usable run and no explicit billing evidence         | no    |
| `STALE_EVIDENCE`      | result or workflow SHA differs from current PR head    | no    |
| `INTERNAL_ERROR`      | validator or classifier violated its own contract      | no    |

Explicit billing evidence requires all of the following:

1. the workflow exists and is active at the current pull-request head;
2. local full validation passes at that exact head;
3. GitHub-owned run/check output identifies billing, spending, included usage,
   storage billing, or an exhausted budget as the reason execution did not
   start; and
4. the check/run conclusion is a startup or action-required failure rather
   than a validator step failure.

Billing usage and budget APIs provide supplementary confirmation when the
token has permission. Their absence never converts `REMOTE_UNKNOWN` into a
billing fallback. A missing run by itself is always `REMOTE_UNKNOWN`.

## Agent Remediation Flow

For each failed in-scope repository task:

1. The controller records the repository, base SHA, current head SHA,
   validator version, failed check IDs, redacted messages, and exact rerun
   command in a fix brief.
2. One fresh fix agent owns that repository only. It may change files relevant
   to the named check IDs and must not weaken or skip the validator.
3. The agent runs the failing check first, implements the repair, then runs
   `fast` and `full` validation.
4. The agent commits and pushes only after both stages pass, then appends RED
   and GREEN evidence to its report.
5. The controller verifies the commit range, reruns full validation, confirms a
   clean worktree, and compares the result SHA with the pull-request head.
6. If hosted validation is available, the controller waits for the current
   head's workflow. If explicit billing evidence exists, it classifies the
   local result as `PASS_LOCAL_FALLBACK` and may merge automatically.

An automated repair gets at most two rounds for the same repository and failed
check set. Success means the controller, not only the implementer, observes a
valid full result at the current PR head. Failure after two rounds is
`FIX_FAILED`; the PR remains open and no merge command runs. A prerequisite
failure is `ENV_BLOCKED` and does not consume a repair round.

The fix report contains:

```text
status: FIXED | UNFIXED | BLOCKED
base_sha: <sha>
head_sha: <sha>
failed_before: <check IDs>
passed_after: <check IDs>
fast_command: <command and exit>
full_command: <command and exit>
commit: <sha or none>
pr: <URL>
concerns: <redacted text or none>
```

## Automatic Merge Rules

Automatic merge is permitted only when all common conditions pass:

- the worktree is clean;
- the intended commit range has completed task review with spec and quality
  approval;
- local full validation passes for the current PR head;
- secret scanning passes;
- the source branch is mergeable and has no unresolved review conversation;
- the state is `PASS_REMOTE` or `PASS_LOCAL_FALLBACK`.

For `PASS_LOCAL_FALLBACK`, the controller posts a PR comment containing only
the validator version, current head SHA, check IDs, local result state, and the
redacted GitHub billing classification. It then performs the repository's
allowed merge method. The comment is evidence, not a substitute for comparing
SHA values immediately before merge.

## Runtime Boundary

Root apply uses the explicit ownership in `root-distribution.yaml`; validator
tooling and CI metadata outside those root-owned paths are not installed into
the runtime.

Named-profile remotes have a different contract. They are exact projections of
the local profile allowlist and contain only canonical `.gitignore`,
`distribution.yaml`, and declared owned paths. A real sync deletes this
document's repository-local tooling bundle from such a mirror. Their
replacement validation gate is:

- the runtime aggregate snapshot preflight and exact-sync result contract;
- the dotfiles repository's pre-commit and `Hermes Bootstrap Tests` GitHub
  Actions workflow; and
- the pinned unit and integration command `task hermes:bootstrap:test`.

See [Hermes Bootstrap Operations](bootstrap.md#source-validation-gate) for the
operator gate and
[Local-Authoritative Profile Sync Design](profile-local-authoritative-sync-design.md#verification-coverage)
for the normative named-mirror behavior and coverage.

## Security

- Validation never reads the real `~/.hermes` runtime home.
- Fixture credentials are unmistakably fake and confined to temporary paths.
- Gitleaks runs before push and in hosted validation.
- JSON messages and PR comments contain no secret values or raw matching
  lines.
- GitHub tokens remain process environment values and never appear in reports,
  command arguments, remotes, or committed files.
- Auto-fix agents may not edit validator code and the file that failed
  validation in the same repair unless the failed check explicitly identifies
  a validator defect and the controller creates a separate tooling task.

## Testing

The in-scope repository guard is tested with fixture repositories for:

- pass, fail, blocked, and internal-error exit codes;
- stable JSON schema and deterministic check ordering;
- secret redaction;
- stale SHA rejection;
- root ownership boundaries;
- missing Docker/image prerequisites;
- successful current-head workflow classification;
- explicit billing startup failure classification;
- no-run `REMOTE_UNKNOWN` classification;
- two-round repair success and `FIX_FAILED` exhaustion.

Named-profile preservation, exact-tree publication, snapshot validation, and
aggregate sync result behavior belong to the replacement dotfiles integration
gate linked above, not this repository-local guard.

## Current Acceptance

For `hermes-home` or another explicitly added source repository, task review
requires both local `fast` and `full` passes and either `PASS_REMOTE` or
`PASS_LOCAL_FALLBACK` at the exact pull-request head. Adding another
repository requires an explicit update to the Repository Contract; the
contract is never inferred from a named-profile manifest entry.

## Non-Normative Historical Note

An earlier version of this design treated then-planned named-profile source
repositories as tooling-bearing repositories and specified sanitized staging,
profile user-data preservation probes, and a multi-repository rollout. Exact
local-authoritative mirroring superseded those assumptions. They are retained
here only as design history and are not current requirements, acceptance
criteria, or rollout instructions for any named profile.

## References

- GitHub workflow run statuses and conclusions:
  <https://docs.github.com/en/rest/actions/workflow-runs?apiVersion=2026-03-10>
- GitHub check conclusion states, including startup failure:
  <https://docs.github.com/en/graphql/reference/checks>
- GitHub Actions billing and included usage:
  <https://docs.github.com/en/actions/concepts/billing-and-usage>
- GitHub budgets that stop metered usage:
  <https://docs.github.com/en/billing/concepts/budgets-and-alerts>
- GitHub billing usage API:
  <https://docs.github.com/en/rest/billing/usage>
