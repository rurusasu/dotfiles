# Hermes Container Bootstrap Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement one containerized `hermes-bootstrap` command that validates credentials and sources, applies root and named-profile distributions, manages shared repositories and `.env` files transactionally, and supplies runtime `gh` authentication on every host OS.

**Architecture:** A Python package baked into the existing Hermes image owns all platform-neutral behavior. Host adapters request a non-secret 1Password item plan and stream raw item JSON as versioned NDJSON to stdin. The bootstrap stages Git sources, completes non-rollbackable remote sync, journals local changes under `/opt/data`, applies declarative content, merges secrets atomically, validates the result, and only then allows the installer to recreate services.

**Tech Stack:** Python 3 standard library, PyYAML already present in the Hermes image, Hermes Agent 0.18.2 Python API, Git, GitHub REST API, Docker Compose, `unittest`

## Global Constraints

- Do not add a host Python dependency; all core code executes in the Hermes image.
- Do not log raw 1Password JSON, secret field values, authorization headers, credential-bearing environment mappings, or authenticated Git URLs.
- Do not pass a secret in a command argument, Compose environment declaration, image layer, persistent payload file, or Git remote URL.
- Use `/opt/data` as `HERMES_HOME`; never initialize `/opt/data` or a named profile as a Git repository.
- Resolve and validate every managed path beneath `/opt/data` before writing. Reject source symlinks and traversal.
- Use the official Hermes profile distribution API to preserve user-owned profile paths.
- Remote commit/push operations finish before the local transaction and remain committed if a later local apply rolls back.
- Test through public module interfaces; use dependency injection for GitHub HTTP, subprocess, clock, and filesystem failure points.
- Keep Python source compatible with the Python version in `nousresearch/hermes-agent:latest` used by the built image.

---

## Task 1: Define manifest, domain models, and stable error codes

**Files:**

- Create: `docker/hermes-agent/bootstrap-manifest.yaml`
- Create: `docker/hermes-agent/bootstrap/hermes_bootstrap/__init__.py`
- Create: `docker/hermes-agent/bootstrap/hermes_bootstrap/errors.py`
- Create: `docker/hermes-agent/bootstrap/hermes_bootstrap/models.py`
- Create: `docker/hermes-agent/bootstrap/hermes_bootstrap/manifest.py`
- Create: `docker/hermes-agent/bootstrap/tests/test_manifest.py`

- [ ] Write failing `unittest` cases named `test_approved_manifest_loads_all_targets`, `test_target_outside_data_root_is_rejected`, and `test_read_write_repository_requires_sync_owner`, plus cases for missing keys, duplicate target names, unsupported schema versions, non-absolute targets, invalid refs, unsupported shared modes, and missing sync owners.

- [ ] Run the test file and confirm it fails because the modules do not exist.

```bash
python3 -m unittest docker/hermes-agent/bootstrap/tests/test_manifest.py -v
```

Expected: import failure for `hermes_bootstrap`.

- [ ] Define immutable dataclasses with these interfaces.

```python
@dataclass(frozen=True)
class OnePasswordField:
    canonical_name: str
    labels: tuple[str, ...]

@dataclass(frozen=True)
class OnePasswordItem:
    key: str
    account: str
    vault: str
    item: str
    fields: tuple[OnePasswordField, ...]

@dataclass(frozen=True)
class DistributionSource:
    name: str
    source: str
    ref: str
    target: Path
    manifest_name: str

@dataclass(frozen=True)
class SharedRepository:
    name: str
    source: str
    ref: str
    target: Path
    mode: Literal["read-only", "read-write"]
    sync_owner: str | None
    legacy_target: Path | None

@dataclass(frozen=True)
class BootstrapManifest:
    schema_version: int
    data_root: Path
    onepassword_items: tuple[OnePasswordItem, ...]
    root_distribution: DistributionSource
    profiles: tuple[DistributionSource, ...]
    shared_repositories: tuple[SharedRepository, ...]
```

- [ ] Define `BootstrapError` subclasses and fixed process exit codes: input `2`, credential `3`, repository `4`, migration `5`, apply `6`, rollback `7`, validation `8`.

- [ ] Add `bootstrap-manifest.yaml` with the confirmed sources:

```yaml
schema_version: 1
data_root: /opt/data
root_distribution:
  name: default
  source: https://github.com/rurusasu/hermes-home.git
  ref: main
  target: /opt/data
  manifest: root-distribution.yaml
profiles:
  - name: rick
    source: https://github.com/rurusasu/hermes-profile-rick.git
    ref: main
    target: /opt/data/profiles/rick
    manifest: distribution.yaml
  - name: hoffman
    source: https://github.com/rurusasu/hermes-profile-hoffman.git
    ref: main
    target: /opt/data/profiles/hoffman
    manifest: distribution.yaml
  - name: risarisa
    source: https://github.com/rurusasu/hermes-profile-risarisa.git
    ref: main
    target: /opt/data/profiles/risarisa
    manifest: distribution.yaml
shared_repositories:
  - name: lifelog
    source: https://github.com/rurusasu/lifelog.git
    ref: main
    target: /opt/data/shared/lifelog
    legacy_target: /opt/data/core/lifelog
    mode: read-write
    sync_owner: default
```

- [ ] Add the six 1Password item declarations using account `my.1password.com`, vault `openclaw`, and items `Hermes Agent Dashboard`, `GitHubUsedOpenClawPAT`, `SlackBot-OpenClaw`, `SlackBot-Rick`, `SlackBot-Hoffman`, and `SlackBot-Risarisa`. Declare label aliases in YAML; do not store values.

- [ ] Implement `load_manifest(path: Path) -> BootstrapManifest` with `yaml.safe_load`, strict unknown-key checks, unique names and targets, GitHub HTTPS source validation, ref validation, and `Path.resolve(strict=False)` containment.

- [ ] Run the tests and `git diff --check`.

```bash
PYTHONPATH=docker/hermes-agent/bootstrap python3 -m unittest docker/hermes-agent/bootstrap/tests/test_manifest.py -v
git diff --check
```

Expected: all manifest tests pass.

## Task 2: Implement the secret-plan and NDJSON input contract

**Files:**

- Create: `docker/hermes-agent/bootstrap/hermes_bootstrap/payload.py`
- Create: `docker/hermes-agent/bootstrap/tests/test_payload.py`

- [ ] Write failing tests for exact secret-plan output, missing header/end records, duplicate items, undeclared item keys, malformed item JSON, missing required fields, label normalization, duplicate matching fields, payload size limits, and secret redaction.

- [ ] Define the stdin protocol exactly:

```json
{"type":"header","schema_version":1}
{"type":"item","key":"github","item":{"id":"item-id","fields":[]}}
{"type":"item","key":"dashboard","item":{"id":"item-id","fields":[]}}
{"type":"end"}
```

Each record is one UTF-8 JSON object. The parser accepts at most 1 MiB per line and 8 MiB total, requires exactly one declared item record per key, and rejects trailing records after `end`.

- [ ] Define typed output used by later modules.

```python
@dataclass(frozen=True)
class SlackSecret:
    bot_token: str
    app_token: str
    allowed_users: str

@dataclass(frozen=True)
class DashboardSecret:
    username: str
    password: str

@dataclass(frozen=True)
class SecretBundle:
    github_token: str
    dashboard: DashboardSecret
    slack_by_profile: Mapping[str, SlackSecret]
    redactor: "SecretRedactor"
```

Implement exact callables `build_secret_plan(manifest: BootstrapManifest) -> dict[str, object]` and `read_secret_payload(stream: TextIO, manifest: BootstrapManifest) -> SecretBundle`.

- [ ] Normalize 1Password field labels case-insensitively after removing spaces, hyphens, and underscores. Require the GitHub `credential` field, dashboard username/password, and every Slack bot/app token plus allowed-user field.

- [ ] Implement `SecretRedactor` to replace all discovered values and Bearer/basic-auth derivatives in exceptions and command summaries. Never include the raw item object in an exception.

- [ ] Run both unit suites.

```bash
PYTHONPATH=docker/hermes-agent/bootstrap python3 -m unittest discover -s docker/hermes-agent/bootstrap/tests -p 'test_*.py' -v
```

Expected: manifest and payload tests pass.

## Task 3: Implement atomic `.env` ownership and dashboard credentials

**Files:**

- Create: `docker/hermes-agent/bootstrap/hermes_bootstrap/envfiles.py`
- Create: `docker/hermes-agent/bootstrap/tests/test_envfiles.py`

- [ ] Write failing tests for an absent file, comments and unmanaged-key preservation, duplicate managed keys, CRLF input, missing final newline, values containing `=`, mode `0600`, atomic replacement, profile-specific Slack separation, and idempotent second apply.

- [ ] Define the managed-key contract:

```python
GITHUB_KEYS = frozenset({
    "GITHUB_PERSONAL_ACCESS_TOKEN", "GH_TOKEN", "GITHUB_TOKEN"
})
DASHBOARD_KEYS = frozenset({
    "HERMES_DASHBOARD_BASIC_AUTH_USERNAME",
    "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH",
    "HERMES_DASHBOARD_BASIC_AUTH_SECRET",
})
SLACK_KEYS = frozenset({
    "SLACK_BOT_TOKEN", "SLACK_APP_TOKEN", "SLACK_ALLOWED_USERS"
})
```

Implement exact callables `merge_env_file(path: Path, managed: Mapping[str, str], remove: AbstractSet[str]) -> bool` and `build_profile_environment(profile: str, secrets: SecretBundle) -> Mapping[str, str]`.

- [ ] Preserve every unmanaged line in original order, remove all existing instances of managed keys, append one canonical managed block, write LF, fsync the temporary file, rename atomically, and enforce `0600` even when content is unchanged.

- [ ] Use `hermes_dashboard.auth.hash_password` and `generate_secret` inside the container to derive the dashboard hash and signing secret from the 1Password password. The plaintext password is never written.

- [ ] Write the same GitHub and dashboard values to root and all managed profiles; write each profile's own Slack values and remove stale shared Slack values before appending.

- [ ] Run the unit suite.

```bash
PYTHONPATH=docker/hermes-agent/bootstrap python3 -m unittest discover -s docker/hermes-agent/bootstrap/tests -p 'test_*.py' -v
```

## Task 4: Validate GitHub and stage immutable source snapshots

**Files:**

- Create: `docker/hermes-agent/bootstrap/hermes_bootstrap/github.py`
- Create: `docker/hermes-agent/bootstrap/hermes_bootstrap/git.py`
- Create: `docker/hermes-agent/bootstrap/tests/test_github.py`
- Create: `docker/hermes-agent/bootstrap/tests/test_git.py`

- [ ] Write failing tests for invalid API credentials, missing repository access, HTTP response redaction, source identity mismatch, missing ref, non-commit resolution, symlinked distribution content, Git command failure redaction, and successful staging at an exact SHA.

- [ ] Implement `GitHubClient` with `urllib.request`, an injectable opener, `Authorization: Bearer`, `X-GitHub-Api-Version`, and methods `authenticated_login() -> str` and `assert_repository_access(owner: str, repo: str) -> None`.

- [ ] Validate `/user` and every root/profile/shared repository before opening the local transaction.

- [ ] Implement a temporary `GIT_ASKPASS` script with mode `0700` that reads `HERMES_BOOTSTRAP_GITHUB_TOKEN` from the child environment. Remove it in `finally`; set `GIT_TERMINAL_PROMPT=0`; never modify the source URL.

- [ ] Define staging interfaces:

```python
@dataclass(frozen=True)
class StagedSource:
    declaration: DistributionSource
    path: Path
    commit: str
```

Implement `stage_distribution(source: DistributionSource, workdir: Path, auth: GitAuth) -> StagedSource` and `assert_safe_distribution_tree(stage: StagedSource) -> None`.

- [ ] Clone with `--no-checkout`, fetch the declared ref, resolve `FETCH_HEAD^{commit}`, check out detached at that SHA, remove `.git`, verify the declared manifest exists, and reject every symlink or special file in the staged tree.

- [ ] Run the unit suite using temporary local bare repositories only.

## Task 5: Apply root and official named-profile distributions

**Files:**

- Create: `docker/hermes-agent/bootstrap/hermes_bootstrap/distributions.py`
- Create: `docker/hermes-agent/bootstrap/tests/test_distributions.py`

- [ ] Write failing root tests for unknown manifest keys, `name != default`, incompatible Hermes version, absent owned paths, nested/overlapping owned paths, symlink sources, preserving unowned runtime files, removing paths owned by the previous version, and idempotency.

- [ ] Write failing profile tests that preserve `.env`, `auth.json`, `memories`, `sessions`, `logs`, and `workspace`; replace `config.yaml`; install missing profiles; update existing non-distribution profiles; and stamp canonical source metadata.

- [ ] Define the root interfaces:

```python
@dataclass(frozen=True)
class RootDistributionManifest:
    schema_version: int
    name: str
    version: str
    hermes_requires: str
    distribution_owned: tuple[PurePosixPath, ...]
```

Implement `load_root_manifest(stage: Path) -> RootDistributionManifest` and `apply_root_distribution(stage: StagedSource, data_root: Path, tx: Transaction) -> ChangeSet`.

- [ ] Store root ownership state at `/opt/data/.bootstrap/root-distribution-state.json`, including source URL, ref, commit, version, and normalized owned paths. Snapshot the prior state and remove only paths present in prior ownership but absent from the new ownership set.

- [ ] Copy files and directories through transaction-owned temporary siblings, preserve executable bits, reject ownership of `.env`, `.git`, `.bootstrap`, `profiles`, `shared`, `core`, locks, memories, sessions, logs, browser data, or OAuth caches.

- [ ] Define the named-profile interface as `apply_profile_distribution(stage: StagedSource, data_root: Path, tx: Transaction) -> ChangeSet`.

- [ ] Set `HERMES_HOME=/opt/data`, invoke `hermes_cli.profile_distribution.install_distribution(str(stage.path), name=stage.declaration.name, force=True)`, and snapshot every staged top-level target except Hermes `USER_OWNED_EXCLUDE` before invocation. This uses the official install API on both first install and declarative replacement, giving `--force-config` semantics without a second unpinned network fetch.

- [ ] After installation, parse the installed `distribution.yaml`, replace its temporary local `source` with the canonical HTTPS source, and write it through Hermes' manifest writer. Preserve the distribution's version and install timestamp.

- [ ] Run the suite inside the real image because it imports Hermes internals.

```bash
docker run --rm -v "$PWD/docker/hermes-agent/bootstrap:/workspace:ro" --entrypoint sh local/hermes-agent-gh:latest -c 'PYTHONPATH=/workspace python -m unittest discover -s /workspace/tests -p "test_*.py" -v'
```

Expected: root and profile tests pass without touching host `~/.hermes`.

## Task 6: Implement shared repository synchronization and migration

**Files:**

- Create: `docker/hermes-agent/bootstrap/hermes_bootstrap/repositories.py`
- Create: `docker/hermes-agent/bootstrap/tests/test_repositories.py`

- [ ] Write failing tests for first clone, read-only fast-forward, non-fast-forward rejection, read-write commit/rebase/push, unchanged sync, lock contention, wrong origin, dirty forbidden paths, legacy-path migration, old/new path collision, compatibility symlink creation, and retry after a later local rollback.

- [ ] Define these interfaces:

```python
@dataclass(frozen=True)
class RemoteSyncResult:
    name: str
    commit: str
    pushed: bool
    working_tree: Path | None
```

Implement `synchronize_remote(repo: SharedRepository, auth: GitAuth) -> RemoteSyncResult` and `apply_shared_working_tree(repo: SharedRepository, result: RemoteSyncResult, tx: Transaction) -> ChangeSet`.

- [ ] Acquire `/opt/data/locks/repositories/<name>.lock` with `fcntl.flock(LOCK_EX | LOCK_NB)`. Treat contention as repository exit code `4` and print the lock path only.

- [ ] Before local transaction start, choose the existing canonical checkout, otherwise the legacy checkout, otherwise no working tree. Validate `remote.origin.url` by normalized owner/repository identity.

- [ ] For `read-only`, require a clean tree, fetch the declared ref, and merge `--ff-only`. For `read-write`, reject `.env`, auth, session, memory, log, cache, credential, and nested `.git` paths; stage allowed changes; commit with `chore: sync Hermes <name>` when needed; fetch; rebase onto the remote ref; and push `HEAD:<ref>`.

- [ ] Keep remote synchronization outside the local rollback boundary. A successful commit/push is valid even when a later distribution apply fails.

- [ ] Inside the local transaction, clone a missing canonical checkout at `RemoteSyncResult.commit`, or atomically move the legacy checkout to the canonical target. If both paths contain real data, raise migration exit code `5`. Create `/opt/data/core/lifelog -> ../shared/lifelog` only after the canonical target is valid.

- [ ] Run repository tests with local bare remotes and two competing lock processes.

## Task 7: Implement the local transaction journal and rollback

**Files:**

- Create: `docker/hermes-agent/bootstrap/hermes_bootstrap/transaction.py`
- Create: `docker/hermes-agent/bootstrap/tests/test_transaction.py`

- [ ] Write failing tests for file, directory, absent-target, symlink, move, mode, and ownership snapshots; reverse-order rollback; interrupted journal recovery; rollback failure reporting; and successful commit cleanup.

- [ ] Define `Transaction.begin(data_root: Path) -> Transaction`, `Transaction.recover_if_needed(data_root: Path) -> None`, `snapshot(path: Path) -> None`, `record_move(source: Path, target: Path) -> None`, `commit() -> None`, and `rollback() -> None`.

- [ ] Store the journal under `/opt/data/.bootstrap/transactions/<uuid>/journal.json`; store backups on the same filesystem for atomic rename. Write and fsync the journal before each target mutation.

- [ ] Reject a second active transaction. At command start, recover an incomplete journal in reverse order before validating a new payload.

- [ ] On apply failure, rollback local root, profile, shared migration, state, and `.env` changes. If rollback itself fails, retain the journal and exit `7` with paths but no file content.

- [ ] On success, fsync affected parent directories, remove backups and journal, and leave only root ownership state under `.bootstrap`.

- [ ] Run the transaction suite with injected failures after every mutation type.

## Task 8: Compose the CLI and final validation

**Files:**

- Create: `docker/hermes-agent/bootstrap/hermes_bootstrap/app.py`
- Create: `docker/hermes-agent/bootstrap/hermes_bootstrap/cli.py`
- Create: `docker/hermes-agent/bootstrap/hermes_bootstrap/__main__.py`
- Create: `docker/hermes-agent/hermes-bootstrap`
- Create: `docker/hermes-agent/bootstrap/tests/test_app.py`
- Create: `docker/hermes-agent/bootstrap/tests/test_cli.py`

- [ ] Write failing orchestration tests proving this order: recover journal, parse manifest/payload, validate credentials and access, stage distributions, synchronize shared remotes, begin transaction, apply root, apply profiles, apply shared working trees, merge environments, validate, commit.

- [ ] Add failure-injection tests after every local stage and assert that remote sync remains while local targets return to their snapshots.

- [ ] Implement CLI commands:

```text
hermes-bootstrap secret-plan --manifest /usr/local/share/hermes-bootstrap/bootstrap-manifest.yaml
hermes-bootstrap apply --manifest /usr/local/share/hermes-bootstrap/bootstrap-manifest.yaml
hermes-bootstrap validate --manifest /usr/local/share/hermes-bootstrap/bootstrap-manifest.yaml
```

`secret-plan` writes one compact non-secret JSON document. `apply` reads NDJSON only from stdin. `validate` reads no secrets and checks the installed layout and file modes without network access.

- [ ] Implement final validation for root ownership state, installed profile names and distribution versions, profile user-owned paths, canonical lifelog identity, compatibility symlink, `.env` mode, required managed keys, and no `.git` at `/opt/data` or `/opt/data/profiles/*`.

- [ ] During credential validation, run an API-equivalent check for each profile environment rather than persisting `gh auth login` state. Report profile names and status only.

- [ ] Map typed exceptions to the fixed exit codes and one redacted stderr line. Unexpected exceptions use apply code `6`; with `HERMES_BOOTSTRAP_DEBUG=1`, print a redacted traceback.

- [ ] Run all package tests in the image.

## Task 9: Install the bootstrap and add an explicit Compose service

**Files:**

- Modify: `docker/hermes-agent/Dockerfile`
- Modify: `docker/hermes-agent/compose.yml`
- Create: `docker/hermes-agent/bootstrap/tests/test_compose_contract.py`

- [ ] Refactor the Dockerfile into `hermes-bootstrap-runtime`, `hermes-bootstrap-test`, and final stages without changing the final image tag. Copy the package to `/usr/local/lib/hermes-bootstrap`, the manifest to `/usr/local/share/hermes-bootstrap/`, and the launcher to `/usr/local/bin/hermes-bootstrap`.

- [ ] Make the launcher execute `/opt/hermes/.venv/bin/python -m hermes_bootstrap` with a fixed `PYTHONPATH`; set executable mode in the image.

- [ ] In the test stage, copy tests and run `python -m unittest discover`; do not install pytest or test dependencies in the final stage.

- [ ] Add `hermes-bootstrap` to Compose with the same build/image and `/opt/data` bind mount as `hermes`, no ports, no restart policy, no dependency on browser services, `HERMES_HOME=/opt/data`, bootstrap profile `bootstrap`, entrypoint `/usr/local/bin/hermes-bootstrap`, and default command `apply`.

- [ ] Change `LIFELOG_ROOT` for the gateway from `/opt/data/core/lifelog` to `/opt/data/shared/lifelog`; retain the compatibility symlink for old scripts.

- [ ] Add contract tests that parse `docker compose config --format json` and assert volume identity, no published ports, no secret environment keys, profile isolation, and the exact entrypoint.

- [ ] Build and validate.

```bash
docker build --target hermes-bootstrap-test -t local/hermes-bootstrap-test docker/hermes-agent
docker compose -f docker/hermes-agent/compose.yml config --quiet
docker compose -f docker/hermes-agent/compose.yml run --rm --no-deps -T hermes-bootstrap secret-plan
```

Expected: image tests pass, Compose is valid, and `secret-plan` prints item metadata without values.

## Task 10: Make runtime `gh` load the active profile environment

**Files:**

- Modify: `docker/hermes-agent/gh-wrapper.sh`
- Create: `docker/hermes-agent/bootstrap/tests/test_gh_wrapper.sh`

- [ ] Write shell tests for credential precedence: existing `GH_TOKEN`; active `${HERMES_HOME}/.env`; `/opt/data/.env` fallback; missing credentials; comments, quotes, and `=` in values; and no value printed on failure.

- [ ] Parse only `GH_TOKEN`, `GITHUB_PERSONAL_ACCESS_TOKEN`, and `GITHUB_TOKEN` from env files without sourcing shell code. Reject NUL and multiline values. Within each file prefer `GH_TOKEN`, then `GITHUB_PERSONAL_ACCESS_TOKEN`, then `GITHUB_TOKEN`.

- [ ] Preserve process `GH_TOKEN` as the highest priority, then active profile env, then root env. Export the resolved value as `GH_TOKEN` and `exec /usr/bin/gh "$@"`.

- [ ] When no token exists, exit non-zero with `GitHub credentials are missing; rerun the Hermes installer.` Do not call `gh auth login` and do not create `hosts.yml`.

- [ ] Run the wrapper tests in the real image and verify root plus named-profile contexts with fixture tokens.

## Task 11: Add repeatable container integration coverage and Taskfile commands

**Files:**

- Create: `docker/hermes-agent/bootstrap/tests/integration/test_bootstrap_flow.py`
- Modify: `Taskfile.yml`

- [ ] Build fixture source repositories and a bare lifelog remote under a temporary directory. Include root/profile declarative files plus runtime sentinel files in the target data root.

- [ ] Start an in-process fake GitHub API that accepts only the fixture token and returns access for the declared fixture repositories. Inject its base URL with `HERMES_BOOTSTRAP_GITHUB_API_URL` only in tests.

- [ ] Cover initial install, idempotent second install, profile config replacement, root-owned deletion, legacy lifelog migration, read-write lifelog push, invalid token with zero target writes, distribution failure rollback, `.env` preservation, and journal recovery.

- [ ] Add these tasks:

```yaml
hermes:bootstrap:test:
  cmds:
    - docker build --target hermes-bootstrap-test -t local/hermes-bootstrap-test docker/hermes-agent

hermes:bootstrap:config:
  cmds:
    - docker compose -f docker/hermes-agent/compose.yml config --quiet
```

- [ ] Remove or replace `hermes:profile:init`, because named profile homes are no longer Git repositories. Keep profile gateway lifecycle tasks.

- [ ] Run focused and baseline checks.

```bash
task hermes:bootstrap:test
task hermes:bootstrap:config
bats tests/bash/hermes_agent.bats
pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1 -Path scripts/powershell/tests/handlers/Handler.HermesAgent.Tests.ps1 -MinimumCoverage 0
git diff --check
```

Expected: bootstrap tests pass; the pre-integration Bats 6 and Pester 57 baseline cases still pass at this phase.

## Completion Criteria

- `docker compose run --rm --no-deps -T hermes-bootstrap apply` is the only implementation of distribution, repository, secret, and migration behavior.
- Invalid/missing GitHub credentials fail before local runtime writes.
- Root and profile runtime state survives updates and injected failures.
- Lifelog is one locked shared checkout, with remote synchronization outside local rollback and migration inside it.
- Runtime `gh` authenticates from the active profile `.env` on every OS without `hosts.yml`.
- Container unit/integration tests and Compose contract checks pass without real credentials.
