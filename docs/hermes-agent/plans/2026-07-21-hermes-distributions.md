# Hermes Distribution Repositories Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert `hermes-home`, Rick, Hoffman, and Risarisa into explicit declarative sources for the OS-independent bootstrap while preserving the writable `lifelog` repository as shared runtime data.

**Architecture:** The three named profiles use Hermes 0.18.2 `distribution.yaml`; the default profile uses the bootstrap-owned `root-distribution.yaml` because Hermes rejects a distribution named `default`. Root-owned config, cron, scripts, policy, and docs move out of dotfiles-generated PowerShell into `rurusasu/hermes-home`. `rurusasu/lifelog` remains a normal read-write Git repository and is never nested in the root distribution.

**Tech Stack:** GitHub private repositories, YAML, Hermes Agent 0.18.2 profile distribution API, Docker, GitHub Actions

## Global Constraints

- Execute each repository change in its own `codex/hermes-distribution-*` branch and worktree.
- Never copy `.env`, `auth.json`, memories, sessions, logs, browser state, OAuth caches, or token values into a source repository.
- Keep `main` as the declared source ref and use pull requests; merge profile repositories before enabling the dotfiles bootstrap.
- Use `hermes_requires: ">=0.18.2"` and start every new distribution manifest at version `0.1.0`.
- Treat `config.yaml`, `SOUL.md`, policy docs, cron definitions, scripts, and MCP declarations as source-repository-owned content after this migration.
- Keep `/opt/data/shared/lifelog` as the canonical runtime path. `/opt/data/core/lifelog` is only a compatibility symlink created by bootstrap.
- Run secret scans and inspect every staged diff before pushing.
- Every distribution repository must contain `.github/workflows/distribution.yml`, `.pre-commit-config.yaml`, `scripts/validate_distribution.py`, tests for that driver, and an ignored `.hermes-validation/` report directory.
- The validator interface is exactly `python3 scripts/validate_distribution.py {fast,full} [--json] [--output PATH]`; validator/schema versions are `1.0.0`/`1`, and exit codes are `0` pass, `1` validation failure, `2` prerequisite unavailable, and `3` internal error.
- JSON contains exactly `schema_version`, `validator_version`, `repository`, `head_sha`, `level`, `status`, `exit_code`, and `checks`; every check contains exactly `id`, `status`, and redacted single-line `message`, where status is `pass`, `fail`, or `blocked`.
- `fast` runs `manifest-schema`, `owned-paths`, `config-contract`, `repository-policy`, and `secret-patterns` in that deterministic order. `full` appends `hermes-parser`, then `user-data-preservation` for named profiles or `root-boundary` for root, then `gitleaks`.
- `secret-patterns` scans only paths returned by `git ls-files --cached --others --exclude-standard -z`; ignored runtime files are outside the source guard, while Git enumeration failure or an unreadable in-scope file fails closed with a redacted count.
- Pin Hermes validation to `docker.io/nousresearch/hermes-agent@sha256:dbd5484b4e822307e78bb68d5bf17a57eece7c5e278ca38b8670df9499f14731` and Gitleaks to `zricethezav/gitleaks@sha256:691af3c7c5a48b16f187ce3446d5f194838f91238f27270ed36eef6359a574d9`; do not use floating tags.
- The pre-commit hook runs `fast`; the pre-push hook runs `full`; both are repository-local hooks and setup installs both hook types. Agents also invoke both commands explicitly because hook presence is not trusted as evidence.
- Fast YAML validation intentionally requires Docker plus the pinned Hermes image and returns prerequisite exit `2` when unavailable. Pull both pinned images before installing hooks; never skip schema checks merely to allow a commit.
- The GitHub workflow runs one Linux `distribution` job on `pull_request` and `workflow_dispatch`, with no push trigger or matrix, `timeout-minutes: 10`, concurrency cancellation, no cache/artifact upload, and checkout pinned to `actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803`.
- A result is current only when JSON `head_sha`, local `HEAD`, and PR `headRefOid` are identical. Automatic merge requires task review approval, a clean worktree, current-head local full pass including Gitleaks, a mergeable PR with no unresolved conversation, and state `PASS_REMOTE` or `PASS_LOCAL_FALLBACK`.
- `PASS_LOCAL_FALLBACK` is allowed only when the workflow is active at the current head and GitHub-owned run/check output explicitly identifies billing, spending, included usage, storage billing, or an exhausted budget as a startup/action-required failure. Missing runs or unavailable billing APIs remain `REMOTE_UNKNOWN` and never permit merge.
- Automated repair receives the failed IDs and exact rerun command, may not weaken the validator, and is limited to two rounds for the same failed check set. Exit `2` is `ENV_BLOCKED` and consumes no repair round; exhausted validation repair is `FIX_FAILED`.

---

## Task 1: Prepare isolated repository worktrees and capture baselines

**Repositories:**

- `rurusasu/hermes-home`
- `rurusasu/hermes-profile-rick`
- `rurusasu/hermes-profile-hoffman`
- `rurusasu/hermes-profile-risarisa`
- `rurusasu/lifelog` (read-only inspection in this task)

- [ ] Create one sibling worktree per repository from its current `main` branch.

```bash
gh repo clone rurusasu/hermes-home ../hermes-home
git -C ../hermes-home worktree add ../hermes-home-distribution -b codex/hermes-distribution-root main
gh repo clone rurusasu/hermes-profile-rick ../hermes-profile-rick
git -C ../hermes-profile-rick worktree add ../hermes-profile-rick-distribution -b codex/hermes-distribution-rick main
gh repo clone rurusasu/hermes-profile-hoffman ../hermes-profile-hoffman
git -C ../hermes-profile-hoffman worktree add ../hermes-profile-hoffman-distribution -b codex/hermes-distribution-hoffman main
gh repo clone rurusasu/hermes-profile-risarisa ../hermes-profile-risarisa
git -C ../hermes-profile-risarisa worktree add ../hermes-profile-risarisa-distribution -b codex/hermes-distribution-risarisa main
```

Expected: every worktree reports a clean branch based on the repository's current `main`.

- [ ] Record the current tracked top-level paths without reading any local runtime home.

```bash
git -C ../hermes-home-distribution ls-tree --name-only HEAD
git -C ../hermes-profile-rick-distribution ls-tree --name-only HEAD
git -C ../hermes-profile-hoffman-distribution ls-tree --name-only HEAD
git -C ../hermes-profile-risarisa-distribution ls-tree --name-only HEAD
```

- [ ] Confirm the current manifests fail the Hermes distribution contract before adding them.

```bash
docker run --rm -v ../hermes-profile-rick-distribution:/distribution:ro --entrypoint python local/hermes-agent-gh:latest -c "from pathlib import Path; from hermes_cli.profile_distribution import plan_install; plan_install('/distribution', Path('/tmp/stage'))"
```

Expected: `DistributionError` reports that `distribution.yaml` is missing. Repeat for Hoffman and Risarisa.

- [ ] Inspect the lifelog repository root and verify that `AGENTS.md` already describes repository-local behavior.

```bash
GH_TOKEN="$(op item get GitHubUsedOpenClawPAT --account my.1password.com --vault openclaw --fields credential --reveal)" gh api repos/rurusasu/lifelog/contents --jq '.[].name'
```

Expected: `AGENTS.md` exists; no distribution manifest is added to `lifelog`.

## Task 2: Convert Rick to an official Hermes distribution

**Files:**

- Create: `../hermes-profile-rick-distribution/distribution.yaml`
- Create: `../hermes-profile-rick-distribution/.github/workflows/distribution.yml`
- Create: `../hermes-profile-rick-distribution/.pre-commit-config.yaml`
- Create: `../hermes-profile-rick-distribution/scripts/validate_distribution.py`
- Create: `../hermes-profile-rick-distribution/tests/test_validate_distribution.py`
- Modify: `../hermes-profile-rick-distribution/.gitignore`
- Modify: `../hermes-profile-rick-distribution/config.yaml`
- Modify: `../hermes-profile-rick-distribution/SOUL.md`
- Verify: `../hermes-profile-rick-distribution/profile.yaml`
- Verify: `../hermes-profile-rick-distribution/slack-manifest.json`

- [ ] Add `distribution.yaml` with the exact distribution identity and owned paths.

```yaml
name: rick
version: 0.1.0
description: Software engineering tech lead profile
hermes_requires: ">=0.18.2"
author: rurusasu
license: private
env_requires:
  - name: X_API_CLIENT_ID
    description: OAuth client ID for the X API MCP server
  - name: X_API_CLIENT_SECRET
    description: OAuth client secret for the X API MCP server
distribution_owned:
  - .no-bundled-skills
  - SOUL.md
  - config.yaml
  - profile.yaml
  - slack-manifest.json
  - assets/
```

- [ ] Normalize `config.yaml` so it contains the intended model, Slack mention policy, terminal environment passthrough, and non-secret MCP declarations. Remove copied GitHub, Slack, dashboard, or profile-specific secret values.

- [ ] Update `SOUL.md` repository policy to name `/opt/data/shared/lifelog` as the shared knowledge repository and to forbid commits from `/opt/data/profiles/rick`.

- [ ] Validate the manifest with the actual Hermes 0.18.2 parser.

```bash
docker run --rm -v ../hermes-profile-rick-distribution:/distribution:ro --entrypoint python local/hermes-agent-gh:latest -c "from pathlib import Path; from hermes_cli.profile_distribution import plan_install; p=plan_install('/distribution', Path('/tmp/stage')); assert p.manifest.name == 'rick'; assert p.manifest.version == '0.1.0'"
```

Expected: exit code `0` and no output.

- [ ] Test user-owned data preservation in a temporary container home.

```bash
docker run --rm -v ../hermes-profile-rick-distribution:/distribution:ro --entrypoint sh local/hermes-agent-gh:latest -c 'set -eu; export HERMES_HOME=/tmp/hermes; mkdir -p /tmp/hermes/profiles/rick/memories; printf keep >/tmp/hermes/profiles/rick/memories/probe; printf SECRET=keep >/tmp/hermes/profiles/rick/.env; hermes profile install /distribution --name rick --force -y; test "$(cat /tmp/hermes/profiles/rick/memories/probe)" = keep; test "$(cat /tmp/hermes/profiles/rick/.env)" = SECRET=keep'
```

Expected: exit code `0`; `.env` and `memories/probe` remain unchanged.

- [ ] Write failing `unittest` cases for the stable JSON schema, deterministic check ordering, all four exit-code classes, secret-message redaction, output atomic replacement, missing Docker/image prerequisite, Hermes parser failure, and preservation of `.env`, `auth.json`, memories, sessions, logs, and workspace. Use temporary fixture repositories only; never mount the real Hermes home.

```bash
python3 -m unittest tests/test_validate_distribution.py -v
```

Expected before implementation: tests fail because the validator contract is absent. Expected after implementation: every fixture case passes.

- [ ] Implement the exact validator CLI and check order from Global Constraints. Repository data names `hermes-profile-rick`, manifest `distribution.yaml`, profile `rick`, and requires `/opt/data/shared/lifelog` plus GitHub token passthrough in `config.yaml`. JSON messages are single-line and redacted; `--output` creates parent directories and uses `os.replace` without printing raw matches.

- [ ] Add local hooks with these exact stages and commands, then install both hook types.

```yaml
repos:
  - repo: local
    hooks:
      - id: hermes-distribution-fast
        name: Hermes distribution fast validation
        entry: python3 scripts/validate_distribution.py fast
        language: system
        pass_filenames: false
        stages: [pre-commit]
      - id: hermes-distribution-full
        name: Hermes distribution full validation
        entry: python3 scripts/validate_distribution.py full
        language: system
        pass_filenames: false
        stages: [pre-push]
```

```bash
pre-commit install --hook-type pre-commit --hook-type pre-push
```

- [ ] Add the one-job workflow. It checks out the exact PR head, runs `python3 scripts/validate_distribution.py full --json --output .hermes-validation/full.json`, prints the JSON to the log and `$GITHUB_STEP_SUMMARY` even on validation failure, and exits with the validator's original code. Do not expose a token or upload the report.

- [ ] Run the guard explicitly, inspect `git diff --check`, amend the existing Rick commit, push PR #2, and wait for the current-head workflow classification.

```bash
python3 -m unittest tests/test_validate_distribution.py -v
python3 scripts/validate_distribution.py fast --json --output .hermes-validation/fast.json
python3 scripts/validate_distribution.py full --json --output .hermes-validation/full.json
git -C ../hermes-profile-rick-distribution diff --check
git -C ../hermes-profile-rick-distribution add .github .pre-commit-config.yaml .gitignore scripts tests distribution.yaml config.yaml SOUL.md profile.yaml slack-manifest.json
git -C ../hermes-profile-rick-distribution commit --amend --no-edit
python3 scripts/validate_distribution.py full --json --output .hermes-validation/full.json
git -C ../hermes-profile-rick-distribution push --force-with-lease -u origin codex/hermes-distribution-rick
gh pr view 2 --repo rurusasu/hermes-profile-rick --json headRefOid,mergeStateStatus,statusCheckRollup
```

Expected: local report `head_sha` equals PR `headRefOid`; remote state becomes `PASS_REMOTE`, or explicit GitHub billing evidence permits `PASS_LOCAL_FALLBACK`. Otherwise leave the PR open.

## Task 3: Convert Hoffman to an official Hermes distribution

**Files:**

- Create: `../hermes-profile-hoffman-distribution/distribution.yaml`
- Create: `../hermes-profile-hoffman-distribution/.github/workflows/distribution.yml`
- Create: `../hermes-profile-hoffman-distribution/.pre-commit-config.yaml`
- Create: `../hermes-profile-hoffman-distribution/scripts/validate_distribution.py`
- Create: `../hermes-profile-hoffman-distribution/tests/test_validate_distribution.py`
- Modify: `../hermes-profile-hoffman-distribution/.gitignore`
- Modify: `../hermes-profile-hoffman-distribution/config.yaml`
- Modify: `../hermes-profile-hoffman-distribution/SOUL.md`
- Verify: `../hermes-profile-hoffman-distribution/profile.yaml`
- Verify: `../hermes-profile-hoffman-distribution/slack-manifest.json`

- [ ] Add the same manifest schema with these identity fields and the same owned-path list as Rick.

```yaml
name: hoffman
version: 0.1.0
description: Financial management profile
hermes_requires: ">=0.18.2"
author: rurusasu
license: private
env_requires:
  - name: X_API_CLIENT_ID
    description: OAuth client ID for the X API MCP server
  - name: X_API_CLIENT_SECRET
    description: OAuth client secret for the X API MCP server
```

- [ ] Normalize non-secret model, Slack, terminal passthrough, and MCP config; update `SOUL.md` to use `/opt/data/shared/lifelog` and forbid profile-home Git commits.

- [ ] Run the parser and preservation tests from Task 2 with `hoffman` substituted for `rick`.

- [ ] Add the complete repository-local validator, tests, local hooks, and one-job workflow defined in Global Constraints. Repository data names `hermes-profile-hoffman`, manifest `distribution.yaml`, profile `hoffman`, and uses `user-data-preservation`. Run the test file once before implementation to record RED, then after implementation to record GREEN.

- [ ] Run `fast` and `full` explicitly, install both hook types, inspect the diff, commit, push, open a PR, and classify the exact current head. Do not merge `REMOTE_PENDING`, `REMOTE_UNKNOWN`, `STALE_EVIDENCE`, `ENV_BLOCKED`, `FAIL_VALIDATION`, `FIX_FAILED`, or `INTERNAL_ERROR`.

```bash
python3 -m unittest tests/test_validate_distribution.py -v
python3 scripts/validate_distribution.py fast --json --output .hermes-validation/fast.json
python3 scripts/validate_distribution.py full --json --output .hermes-validation/full.json
pre-commit install --hook-type pre-commit --hook-type pre-push
git -C ../hermes-profile-hoffman-distribution diff --check
git -C ../hermes-profile-hoffman-distribution add .github .pre-commit-config.yaml .gitignore scripts tests distribution.yaml config.yaml SOUL.md profile.yaml slack-manifest.json
git -C ../hermes-profile-hoffman-distribution commit -m "feat: publish Hoffman Hermes distribution"
python3 scripts/validate_distribution.py full --json --output .hermes-validation/full.json
git -C ../hermes-profile-hoffman-distribution push -u origin codex/hermes-distribution-hoffman
gh pr create --repo rurusasu/hermes-profile-hoffman --base main --head codex/hermes-distribution-hoffman --title "feat: publish Hoffman Hermes distribution" --body "Adds the Hermes 0.18.2 distribution manifest and canonical declarative profile configuration."
```

## Task 4: Convert Risarisa to an official Hermes distribution

**Files:**

- Create: `../hermes-profile-risarisa-distribution/distribution.yaml`
- Create: `../hermes-profile-risarisa-distribution/.github/workflows/distribution.yml`
- Create: `../hermes-profile-risarisa-distribution/.pre-commit-config.yaml`
- Create: `../hermes-profile-risarisa-distribution/scripts/validate_distribution.py`
- Create: `../hermes-profile-risarisa-distribution/tests/test_validate_distribution.py`
- Modify: `../hermes-profile-risarisa-distribution/.gitignore`
- Modify: `../hermes-profile-risarisa-distribution/config.yaml`
- Modify: `../hermes-profile-risarisa-distribution/SOUL.md`
- Verify: `../hermes-profile-risarisa-distribution/slack-manifest.json`

- [ ] Add a manifest that lists only paths actually present in this repository. Do not invent a `profile.yaml` role contract.

```yaml
name: risarisa
version: 0.1.0
description: Dedicated Risarisa Hermes profile
hermes_requires: ">=0.18.2"
author: rurusasu
license: private
env_requires:
  - name: X_API_CLIENT_ID
    description: OAuth client ID for the X API MCP server
  - name: X_API_CLIENT_SECRET
    description: OAuth client secret for the X API MCP server
distribution_owned:
  - .no-bundled-skills
  - SOUL.md
  - config.yaml
  - slack-manifest.json
```

- [ ] Normalize non-secret model, Slack, terminal passthrough, and MCP config; update `SOUL.md` to use `/opt/data/shared/lifelog` and forbid profile-home Git commits.

- [ ] Run the parser and preservation tests from Task 2 with `risarisa` substituted for `rick`.

- [ ] Add the complete repository-local validator, tests, local hooks, and one-job workflow defined in Global Constraints. Repository data names `hermes-profile-risarisa`, manifest `distribution.yaml`, profile `risarisa`, and uses `user-data-preservation`. Run the test file once before implementation to record RED, then after implementation to record GREEN.

- [ ] Run `fast` and `full` explicitly, install both hook types, inspect the diff, commit, push, open a PR, and classify the exact current head. Apply the same non-merge states and two-round repair limit as Hoffman.

```bash
python3 -m unittest tests/test_validate_distribution.py -v
python3 scripts/validate_distribution.py fast --json --output .hermes-validation/fast.json
python3 scripts/validate_distribution.py full --json --output .hermes-validation/full.json
pre-commit install --hook-type pre-commit --hook-type pre-push
git -C ../hermes-profile-risarisa-distribution diff --check
git -C ../hermes-profile-risarisa-distribution add .github .pre-commit-config.yaml .gitignore scripts tests distribution.yaml config.yaml SOUL.md slack-manifest.json
git -C ../hermes-profile-risarisa-distribution commit -m "feat: publish Risarisa Hermes distribution"
python3 scripts/validate_distribution.py full --json --output .hermes-validation/full.json
git -C ../hermes-profile-risarisa-distribution push -u origin codex/hermes-distribution-risarisa
gh pr create --repo rurusasu/hermes-profile-risarisa --base main --head codex/hermes-distribution-risarisa --title "feat: publish Risarisa Hermes distribution" --body "Adds the Hermes 0.18.2 distribution manifest and canonical declarative profile configuration."
```

## Task 5: Define the default/root distribution contract

**Files:**

- Create: `../hermes-home-distribution/root-distribution.yaml`
- Create: `../hermes-home-distribution/.github/workflows/distribution.yml`
- Create: `../hermes-home-distribution/.pre-commit-config.yaml`
- Create: `../hermes-home-distribution/scripts/validate_distribution.py`
- Create: `../hermes-home-distribution/tests/test_validate_distribution.py`
- Modify: `../hermes-home-distribution/.gitignore`
- Modify: `../hermes-home-distribution/config.yaml`
- Modify: `../hermes-home-distribution/SOUL.md`
- Modify: `../hermes-home-distribution/profile.yaml`
- Modify: `../hermes-home-distribution/slack-manifest.json`
- Create or modify: `../hermes-home-distribution/docs/profile-home-layout.md`
- Create or modify: `../hermes-home-distribution/docs/slack-app-registration.md`

- [ ] Add the bootstrap-owned root manifest with explicit replacement boundaries.

```yaml
schema_version: 1
name: default
version: 0.1.0
description: Default Hermes root profile
hermes_requires: ">=0.18.2"
distribution_owned:
  - SOUL.md
  - config.yaml
  - profile.yaml
  - slack-manifest.json
  - assets/
  - cron/
  - docs/
  - skills/
```

Repository tooling remains under `scripts/validate_distribution.py`, but `scripts/` is deliberately not root-owned and therefore is never copied into `/opt/data`.

- [ ] Port the final declarative behavior currently emitted by `Handler.HermesAgent.ps1` into `config.yaml`: model selection, Slack mention policy, terminal GitHub-token passthrough, Browser MCP, X docs, and the X API wrapper. Store endpoint names and commands only; store no credentials.

- [ ] Update `SOUL.md` and `docs/profile-home-layout.md` to state that `/opt/data` and `/opt/data/profiles/*` are runtime homes, not Git repositories; all profiles read and write the single `/opt/data/shared/lifelog` checkout.

- [ ] Port the Slack registration guide currently generated by PowerShell into `docs/slack-app-registration.md`, using environment variable names and the configured viewer port rather than embedded credentials.

- [ ] Verify every `distribution_owned` entry exists and all resolved paths remain under the checkout.

```bash
docker run --rm -v ../hermes-home-distribution:/distribution:ro --entrypoint python local/hermes-agent-gh:latest -c "from pathlib import Path; import yaml; root=Path('/distribution').resolve(); data=yaml.safe_load((root/'root-distribution.yaml').read_text()); assert data['schema_version']==1; missing=[p for p in data['distribution_owned'] if not (root/p.rstrip('/')).exists()]; assert not missing, missing; assert all((root/p.rstrip('/')).resolve().is_relative_to(root) for p in data['distribution_owned'])"
```

Expected: exit code `0` and no output.

- [ ] Write the root validator tests before implementation. Cover the same schema, ordering, exit, redaction, output, and prerequisite cases as named profiles, but replace the preservation probe with `root-boundary` fixtures that reject reserved/mutable ownership, overlap, traversal, symlinks, and special files while proving unowned runtime sentinels remain untouched.

- [ ] Add the complete repository-local validator, hooks, and one-job workflow from Global Constraints. Repository data names `hermes-home`, manifest `root-distribution.yaml`, profile `default`, and the full-only root check is `root-boundary`. Run tests RED then GREEN, followed by explicit `fast` and `full` JSON reports.

- [ ] Run root guard checks, stage only the root contract and guard, and commit the independently reviewable Task 5 deliverable. Do not push until Task 6 adds the common-sync cron contract.

```bash
python3 -m unittest tests/test_validate_distribution.py -v
python3 scripts/validate_distribution.py fast --json --output .hermes-validation/fast.json
python3 scripts/validate_distribution.py full --json --output .hermes-validation/full.json
git diff --check
git add .github .pre-commit-config.yaml .gitignore root-distribution.yaml SOUL.md config.yaml profile.yaml slack-manifest.json docs scripts/validate_distribution.py tests skills assets
git commit -m "feat: define Hermes root distribution"
```

## Task 6: Replace root-home Git sync with the common bootstrap command

**Files:**

- Delete: `../hermes-home-distribution/scripts/hermes_home_sync.sh`
- Modify: `../hermes-home-distribution/cron/jobs.json`
- Modify: `../hermes-home-distribution/SOUL.md`

- [ ] Delete `scripts/hermes_home_sync.sh` and do not add another distribution-owned Git implementation.

- [ ] Replace the obsolete root-home sync cron entry with a default-profile-only lifelog sync job invoking `/usr/local/bin/hermes-bootstrap sync-repository lifelog`. Preserve the article-news Slack job, but point all content paths at `/opt/data/shared/lifelog`.

- [ ] Keep authentication, repository identity validation, locking, forbidden-path checks, commit, rebase, and push inside the common bootstrap command. The cron definition contains no credential or Git command.

- [ ] Add shell syntax and JSON checks.

```bash
jq -e '.jobs | type == "array"' ../hermes-home-distribution/cron/jobs.json
rg -n '/opt/data/core/lifelog|hermes_home_sync|/opt/data/.git' ../hermes-home-distribution
rg -n 'git (add|commit|fetch|pull|rebase|push)|GIT_ASKPASS' ../hermes-home-distribution/scripts ../hermes-home-distribution/cron
```

Expected: the JSON check passes and both searches return no stale runtime-root or duplicated Git-sync implementation.

- [ ] Validate the root manifest again, run repository checks, inspect the full diff, and scan for credentials.

```bash
python3 -m unittest tests/test_validate_distribution.py -v
python3 scripts/validate_distribution.py fast --json --output .hermes-validation/fast.json
python3 scripts/validate_distribution.py full --json --output .hermes-validation/full.json
pre-commit install --hook-type pre-commit --hook-type pre-push
git -C ../hermes-home-distribution diff --check
git -C ../hermes-home-distribution grep -nE 'ghp_[A-Za-z0-9]+|xox[baprs]-|HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=' -- ':!*.example' ':!*.md'
```

Expected: `git diff --check` succeeds and the credential search prints nothing.

- [ ] Commit the Task 6 cron/policy delta, rerun the exact-head full validator, push both reviewed commits, open a PR, and classify the current-head workflow.

```bash
git -C ../hermes-home-distribution add cron/jobs.json SOUL.md scripts/hermes_home_sync.sh
git -C ../hermes-home-distribution commit -m "feat: centralize Hermes lifelog sync"
python3 scripts/validate_distribution.py full --json --output .hermes-validation/full.json
git -C ../hermes-home-distribution push -u origin codex/hermes-distribution-root
gh pr create --repo rurusasu/hermes-home --base main --head codex/hermes-distribution-root --title "feat: define Hermes root distribution" --body "Defines the root-owned declarative paths and moves shared lifelog policy and sync behavior into the Hermes source repository."
```

## Task 7: Merge and pin the source-repository contract

- [ ] For each PR, rerun `full --json` in a clean current-head worktree, require report `head_sha == git rev-parse HEAD == gh pr view --json headRefOid`, and verify the reviewed commit range is unchanged.

- [ ] Classify remote evidence as one of `PASS_REMOTE`, `PASS_LOCAL_FALLBACK`, `FAIL_VALIDATION`, `FIX_FAILED`, `ENV_BLOCKED`, `REMOTE_PENDING`, `REMOTE_UNKNOWN`, `STALE_EVIDENCE`, or `INTERNAL_ERROR`. A successful current-head workflow is `PASS_REMOTE`. A missing run is `REMOTE_UNKNOWN`; it is never inferred to be billing.

- [ ] When validation fails, create a fix brief containing repository, base/head SHA, validator version, failed IDs and redacted messages, and the exact rerun command. Dispatch one fresh fix agent, require RED then `fast` and `full` GREEN evidence, independently rerun full at the new PR head, and stop after two repair rounds for the same failed set.

- [ ] For explicit billing startup failure only, post a PR comment containing validator version, current head SHA, passed check IDs, `PASS_LOCAL_FALLBACK`, and a redacted GitHub billing classification. Re-read `headRefOid` immediately after the comment and before merging.

- [ ] Merge the three named-profile PRs only in `PASS_REMOTE` or `PASS_LOCAL_FALLBACK`, after task review approval, clean worktree, secret pass, mergeability, and no unresolved review conversations.

- [ ] Merge the `hermes-home` PR under the same gate after the named distributions are available.

- [ ] Record each merged `main` commit SHA in the dotfiles bootstrap implementation PR description for auditability; the runtime manifest continues tracking `main` as approved.

- [ ] Re-run remote manifest validation directly from fresh clones using the Hermes image.

```bash
docker run --rm --entrypoint hermes local/hermes-agent-gh:latest profile install --help
docker run --rm --entrypoint hermes local/hermes-agent-gh:latest profile update --help
```

Expected: install exposes `--force`; update exposes `--force-config`, confirming the target Hermes CLI contract.

- [ ] Confirm `rurusasu/lifelog` remains a standalone repository with `AGENTS.md`, no `distribution.yaml`, and no Hermes runtime secrets.

## Completion Criteria

- All four source PRs are merged with `PASS_REMOTE`, or with a documented `PASS_LOCAL_FALLBACK` only when GitHub explicitly reports a billing startup block.
- Rick, Hoffman, and Risarisa pass Hermes 0.18.2 distribution parsing and user-data preservation probes.
- `hermes-home/root-distribution.yaml` owns only explicit declarative paths.
- Root cron invokes the common bootstrap to sync `/opt/data/shared/lifelog`; no distribution code treats `/opt/data` as a Git checkout or implements Git synchronization.
- No source repository contains a secret or mutable Hermes runtime path.
