# Hermes Distribution Validation Design

## Status

Approved design for repository-local validation, GitHub Actions fallback, and
agent-driven remediation across the Hermes root and named-profile source
repositories.

## Problem

The Hermes distribution repositories need hosted pull-request checks, but
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

- Give every distribution repository the same self-contained local guard.
- Run the same full validation contract locally and in GitHub Actions.
- Minimize hosted runner usage without weakening pull-request validation.
- Distinguish code failures, local prerequisite failures, stale evidence,
  unknown remote failures, and explicit GitHub billing blocks.
- Allow automatic merge from local evidence only for an explicitly identified
  billing block.
- Define when an agent repair succeeded, failed, or requires human/context
  intervention.
- Keep repository tooling and CI metadata out of installed Hermes profile
  homes.

## Non-Goals

- Replacing GitHub Actions when hosted execution is available.
- Automatically merging when no workflow run appears for an unknown reason.
- Allowing agents to bypass failed local validation with `--no-verify`.
- Sharing a private remote pre-commit plugin that introduces another
  authentication and availability dependency.
- Copying generated validation reports into Git history.

## Repository Contract

Each of these repositories carries the same thin guard implementation:

- `rurusasu/hermes-home`;
- `rurusasu/hermes-profile-rick`;
- `rurusasu/hermes-profile-hoffman`;
- `rurusasu/hermes-profile-risarisa`.

Required paths are:

```text
.github/workflows/distribution.yml
.pre-commit-config.yaml
scripts/validate_distribution.py
.gitignore
```

The Python driver contains no YAML implementation of its own. It invokes the
pinned Hermes image for distribution parsing and installation behavior, and a
pinned Gitleaks image for secret scanning. Keeping the driver repository-local
allows a fresh clone to validate without access to another private repository.
The small amount of duplicated orchestration is preferable to a networked
pre-commit dependency.

The driver reads identity and owned paths from `distribution.yaml`, or from
`root-distribution.yaml` for `hermes-home`. Repository-specific assertions are
declared as data near the top of the driver rather than implemented as
different control flow.

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

`full` runs every fast check plus:

- `hermes-parser`;
- `user-data-preservation` for named profiles or `root-boundary` for root;
- `gitleaks`.

The user-data preservation probe runs as the image's `hermes` user because the
Hermes CLI shim drops root to UID 10000. It asserts that `.env`, auth, memory,
session, log, and workspace sentinels remain unchanged after forced
distribution installation.

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
  "repository": "hermes-profile-rick",
  "head_sha": "0123456789abcdef",
  "level": "full",
  "status": "pass",
  "exit_code": 0,
  "checks": [
    {
      "id": "hermes-parser",
      "status": "pass",
      "message": "Hermes distribution contract accepted"
    }
  ]
}
```

Allowed check statuses are `pass`, `fail`, and `blocked`. Messages are
redacted, single-line summaries. A result is valid only when `head_sha` equals
both local `HEAD` and the pull request's current `headRefOid`.

Generated reports live under `.hermes-validation/`, which every repository
ignores.

## Local Git Guards

`.pre-commit-config.yaml` defines repository-local hooks:

- pre-commit stage: `validate_distribution.py fast`;
- pre-push stage: `validate_distribution.py full`.

Repository setup installs both hooks:

```text
pre-commit install --hook-type pre-commit --hook-type pre-push
```

Agents must also invoke both stages explicitly before reporting completion.
The controller does not trust hook execution because Git hooks can be absent or
bypassed; it reruns full validation independently for the exact commit.

## GitHub Actions Guard

Each repository has one `distribution` workflow with one Linux job. It runs on
`pull_request` and manual dispatch, not on both pull request and branch push.
It uses:

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

For each failed repository task:

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

## Runtime Isolation

Hermes 0.18.2 copies most top-level distribution repository files during
installation. Adding `.github`, `.pre-commit-config.yaml`, and validator
scripts would therefore pollute profile runtime homes if the raw checkout were
installed.

The common bootstrap constructs a sanitized temporary profile payload before
calling Hermes' official distribution API. The payload contains only:

- `distribution.yaml`;
- paths declared by `distribution_owned`.

It rejects missing, overlapping, traversing, symlinked, or special-file owned
paths. CI metadata, local hooks, repository `.gitignore`, and validator tooling
remain in the source checkout and never reach `/opt/data/profiles/<name>`.

Root apply already uses explicit `root-distribution.yaml` ownership and follows
the same exclusion rule.

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

The guard itself is tested with fixture repositories for:

- pass, fail, blocked, and internal-error exit codes;
- stable JSON schema and deterministic check ordering;
- secret redaction;
- stale SHA rejection;
- named-profile preservation and root ownership boundaries;
- missing Docker/image prerequisites;
- successful current-head workflow classification;
- explicit billing startup failure classification;
- no-run `REMOTE_UNKNOWN` classification;
- two-round repair success and `FIX_FAILED` exhaustion;
- sanitized profile payload excluding `.github`, hooks, and tooling.

## Rollout

1. Amend the open Rick pull request with the local guard and GitHub Actions.
2. Apply the same guard contract to Hoffman and Risarisa while creating their
   distribution manifests.
3. Add the root variant to `hermes-home`.
4. Require task review and either `PASS_REMOTE` or
   `PASS_LOCAL_FALLBACK` before merging each source repository.
5. Implement sanitized named-profile staging in the container bootstrap before
   installing the merged source repositories into a real runtime.

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
