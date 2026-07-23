# Hermes Profile Local-Authoritative Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mirror each installed named profile's locally owned declarative files to its GitHub repository during bootstrap and every two hours, while keeping runtime state and secrets local.

**Architecture:** A new snapshot module validates and copies the local allowlist into private immutable staging. A separate Git module builds an exact tree with Git plumbing, commits on the configured remote head, and retries one push race without ever making a profile home a checkout. The existing bootstrap orchestrator syncs existing profiles before staging exact commits; the remote-authoritative `hermes-home` distribution supplies one root-owned cron wrapper and job.

**Tech Stack:** Python 3, PyYAML, Hermes Agent 0.18.2 profile API, bounded `/usr/bin/git` subprocesses, Docker Compose, `unittest`, Bash, JSON, GitHub CLI

## Global Constraints

- `/opt/data/profiles/{name}` is authoritative for existing named profiles; cron is strictly local to remote.
- Synchronize only canonical `distribution.yaml`, generated `.gitignore`, and regular files under validated local `distribution_owned` paths.
- Remove `source` and `installed_at` from the remote manifest and reject every unknown manifest key.
- Reject `.env`, `auth.json`, credentials, tokens, runtime directories, Git metadata, symlinks, external hardlinks, special files, traversal, case collisions, and high-confidence secret content before any push.
- Never initialize `/opt/data` or `/opt/data/profiles/{name}` as a Git repository.
- Build Git commits in a private temporary repository with an exact empty-index projection; never check out an untrusted remote profile tree.
- Never force-push. Retry one non-fast-forward race by rebuilding the same local tree on the newest remote head.
- Preflight all installed profiles before the first push. A failed aggregate preflight pushes none.
- After preflight, continue with later profiles when one Git operation fails; report `changed`, `unchanged`, or `failed` for every profile and exit nonzero on any failure.
- A bootstrap profile-sync failure occurs before `Transaction.begin`, runtime distribution apply, and host-adapter restart.
- A missing target may seed from remote only during first-install bootstrap. Cron treats every missing profile as failure.
- Keep root `hermes-home` remote-authoritative and shared `lifelog` on its existing locked read-write workflow.
- Keep tokens in the existing `GitAuth`/askpass path. Never print file contents, environment values, authenticated URLs, or secret-bearing subprocess state.
- Run the implementation inside the pinned Hermes image; do not add a host Python dependency.
- The profile repositories' default branches become exact mirrors and therefore do not retain `.github`, pre-commit, validators, tests, README files, or other remote-only content.
- Do not commit directly to `main`. Use `codex/hermes-profile-local-sync` for dotfiles and a fresh `codex/hermes-profile-sync-cron` branch for `hermes-home`.

## Workspace And File Map

Use these isolated worktrees during execution:

```text
/Users/ktome1995/Program/dotfiles-hermes-profile-sync
/Users/ktome1995/Program/hermes-home-profile-sync
```

The primary dotfiles checkout at `/Users/ktome1995/Program/dotfiles` is on an unrelated branch and must remain untouched.

Files and responsibilities:

```text
dotfiles/docker/hermes-agent/bootstrap/hermes_bootstrap/profile_snapshot.py
  Local manifest parsing, allowlist generation, safe immutable snapshots.

dotfiles/docker/hermes-agent/bootstrap/hermes_bootstrap/profile_sync.py
  Exact Git-tree construction, diff reporting, commit, push, retry, aggregate result.

dotfiles/docker/hermes-agent/bootstrap/hermes_bootstrap/app.py
  Runtime token boundary and bootstrap ordering for existing/missing profiles.

dotfiles/docker/hermes-agent/bootstrap/hermes_bootstrap/cli.py
  sync-profiles command, --dry-run, JSON output with nonzero result status.

dotfiles/docker/hermes-agent/bootstrap/tests/test_profile_snapshot.py
dotfiles/docker/hermes-agent/bootstrap/tests/test_profile_sync.py
  Focused unit/security tests for the two new modules.

dotfiles/docker/hermes-agent/bootstrap/tests/test_app.py
dotfiles/docker/hermes-agent/bootstrap/tests/test_cli.py
  Orchestration, token, result, and exit-code tests.

dotfiles/docker/hermes-agent/bootstrap/tests/integration/test_profile_sync_flow.py
  Three-profile bare-remote and bootstrap integration tests.

dotfiles/docs/hermes-agent/{bootstrap-design.md,bootstrap.md,profile-home-layout.md}
  Operational source-of-truth and command documentation.

hermes-home/scripts/profile_sync.sh
  Thin root cron wrapper.

hermes-home/{root-distribution.yaml,cron/jobs.json}
  Root ownership and two-hour cron definition.

hermes-home/{scripts/validate_distribution.py,tests/test_validate_distribution.py}
  Root distribution contract and regression coverage for the third runtime job.
```

For fast test-driven cycles after the baseline image exists, use:

```bash
docker run --rm \
  -v "$PWD/docker/hermes-agent/bootstrap:/workspace/bootstrap:ro" \
  -e PYTHONPATH=/workspace/bootstrap \
  --entrypoint /opt/hermes/.venv/bin/python \
  local/hermes-bootstrap-test \
  -m unittest discover -s /workspace/bootstrap/tests \
  -p 'test_profile_snapshot.py' -v
```

The final dotfiles gate is always `task hermes:bootstrap:test`; the bind-mounted command is only the inner TDD loop.

---

### Task 1: Build Canonical Local Profile Snapshots

**Files:**

- Create: `docker/hermes-agent/bootstrap/hermes_bootstrap/profile_snapshot.py`
- Create: `docker/hermes-agent/bootstrap/tests/test_profile_snapshot.py`
- Reuse: `docker/hermes-agent/bootstrap/hermes_bootstrap/distributions.py:130-144,349-376,545-600`
- Reuse: `docker/hermes-agent/bootstrap/hermes_bootstrap/filesystem.py`

**Interfaces:**

- Consumes: `BootstrapManifest.profiles`, `DistributionSource.target`, the installed Hermes 0.18.2 manifest parser, and a caller-owned private scratch directory.
- Produces: `prepare_profile_snapshots(manifest, scratch_root, allow_missing=...)`, `ProfileSnapshot`, `PreparedProfiles`, and deterministic snapshot digests used by Git sync and production verification.

- [ ] **Step 1: Write failing manifest and allowlist tests**

Add tests with these exact public expectations:

```python
def test_canonical_manifest_strips_runtime_fields_and_rejects_unknown_keys(self) -> None:
    snapshot = self.prepare("rick", owned=["SOUL.md", "assets"])
    payload = yaml.safe_load(snapshot.manifest_bytes)
    self.assertNotIn("source", payload)
    self.assertNotIn("installed_at", payload)
    self.assertEqual(payload["distribution_owned"], ["SOUL.md", "assets"])

def test_gitignore_is_an_exact_root_allowlist_with_nested_parents(self) -> None:
    snapshot = self.prepare("rick", owned=["SOUL.md", "assets/icons"])
    self.assertEqual(
        snapshot.gitignore_bytes.decode("ascii").splitlines(),
        [
            "/*", "!/.gitignore", "!/distribution.yaml", "!/SOUL.md",
            "!/assets/", "!/assets/icons/", "!/assets/icons/**",
        ],
    )
```

Cover duplicate YAML keys, all Hermes declarative keys, runtime `source` and `installed_at`, unknown keys, wrong profile identity, empty ownership, overlapping paths, non-portable path characters, and deterministic ordering.
Also reject attempts to declare `.gitignore` or `distribution.yaml` as an owned
path because the synchronizer owns those two control files.

- [ ] **Step 2: Run the focused test and verify RED**

```bash
docker run --rm -v "$PWD/docker/hermes-agent/bootstrap:/workspace/bootstrap:ro" \
  -e PYTHONPATH=/workspace/bootstrap \
  --entrypoint /opt/hermes/.venv/bin/python local/hermes-bootstrap-test \
  -m unittest discover -s /workspace/bootstrap/tests \
  -p 'test_profile_snapshot.py' -v
```

Expected: FAIL with `ModuleNotFoundError: hermes_bootstrap.profile_snapshot`.

- [ ] **Step 3: Define immutable snapshot types and canonicalization**

Implement these interfaces:

```python
ProfileMode = Literal[0o644, 0o755]

@dataclass(frozen=True)
class SnapshotEntry:
    path: PurePosixPath
    mode: ProfileMode
    size: int
    sha256: str

@dataclass(frozen=True)
class ProfileSnapshot:
    declaration: DistributionSource
    root: Path
    manifest_bytes: bytes
    gitignore_bytes: bytes
    entries: tuple[SnapshotEntry, ...]
    digest: str

@dataclass(frozen=True)
class PreparedProfiles:
    snapshots: tuple[ProfileSnapshot, ...]
    missing: tuple[DistributionSource, ...]
```

Define `ProfileSnapshotError(RepositoryError)` with immutable `profile` and
`category` fields. Implement the exact callable signature
`prepare_profile_snapshots(manifest: BootstrapManifest, scratch_root: Path, *,
allow_missing: bool) -> PreparedProfiles`.

Use the exact allowed manifest key set:

```python
_DECLARATIVE_KEYS = (
    "name", "version", "description", "hermes_requires", "author",
    "license", "env_requires", "distribution_owned",
)
_RUNTIME_KEYS = frozenset({"source", "installed_at"})
```

Parse with the duplicate-key-rejecting loader already used by distributions, call `_read_profile_manifest_at(..., require_sources=True)` for Hermes compatibility, replace `distribution_owned` with normalized POSIX paths, and serialize with `yaml.safe_dump(..., sort_keys=False, allow_unicode=False)`.

- [ ] **Step 4: Implement deterministic `.gitignore` generation**

Add an internal function with a source-kind mapping so files receive one rule and owned directories receive parent, directory, and descendant rules:

```python
def _render_gitignore(
    owned: tuple[PurePosixPath, ...],
    directory_paths: frozenset[PurePosixPath],
) -> bytes:
    rules = ["/*", "!/.gitignore", "!/distribution.yaml"]
    seen = set(rules)

    def add(rule: str) -> None:
        if rule not in seen:
            seen.add(rule)
            rules.append(rule)

    for path in owned:
        for depth in range(1, len(path.parts)):
            add(f"!/{'/'.join(path.parts[:depth])}/")
        logical = path.as_posix()
        if path in directory_paths:
            add(f"!/{logical}/")
            add(f"!/{logical}/**")
        else:
            add(f"!/{logical}")
    return ("\n".join(rules) + "\n").encode("ascii")
```

Start every file with `/*`, `!/.gitignore`, and `!/distribution.yaml`; de-duplicate rules without sorting away the normalized owned-path order; end with exactly one newline.

- [ ] **Step 5: Write failing filesystem-boundary tests**

Add table-driven tests for:

```python
for unsafe in (
    ".env", "auth.json", ".git/config", "memories", "sessions", "logs",
    "plans", "workspace", "home", "cron/output", "cron/state", "locks",
):
    with self.subTest(unsafe=unsafe), self.assertRaises(ProfileSnapshotError):
        self.prepare("rick", owned=[unsafe])
```

Also cover a nested symlink, FIFO, socket, external hardlink, unreadable file, directory ancestor swap, file replacement during read, case-fold collision, GitHub/Slack token bytes, private-key headers, and cleanup after failure. Include positive Rick/Hoffman avatar and portfolio files and prove RisaRisa has no `assets` entry unless its manifest declares it.

- [ ] **Step 6: Run the new boundary tests and verify RED**

```bash
docker run --rm -v "$PWD/docker/hermes-agent/bootstrap:/workspace/bootstrap:ro" \
  -e PYTHONPATH=/workspace/bootstrap \
  --entrypoint /opt/hermes/.venv/bin/python local/hermes-bootstrap-test \
  -m unittest discover -s /workspace/bootstrap/tests \
  -p 'test_profile_snapshot.py' -v
```

Expected: the new unsafe-source tests fail because snapshot copying is not implemented.

- [ ] **Step 7: Implement descriptor-anchored immutable copying**

Walk only declared paths with `os.scandir` and `follow_symlinks=False`. Open regular files with `O_NOFOLLOW | O_CLOEXEC`, require `st_nlink == 1`, and compare device, inode, size, and `st_mtime_ns` before and after the bounded read. Write only to mode `0600` private scratch, then apply Git mode `0644` or `0755` in the snapshot.

Scan bytes using the existing validator's high-confidence GitHub PAT, Slack token, and private-key patterns. Reject credential filename stems and all `.env*` names without printing the path content. Build `digest` from sorted `path NUL mode NUL sha256` records, not from absolute paths.

- [ ] **Step 8: Run focused tests and verify GREEN**

```bash
docker run --rm -v "$PWD/docker/hermes-agent/bootstrap:/workspace/bootstrap:ro" \
  -e PYTHONPATH=/workspace/bootstrap \
  --entrypoint /opt/hermes/.venv/bin/python local/hermes-bootstrap-test \
  -m unittest discover -s /workspace/bootstrap/tests \
  -p 'test_profile_snapshot.py' -v
```

Expected: all `test_profile_snapshot` cases pass and scratch contains only `distribution.yaml`, `.gitignore`, and owned entries.

- [ ] **Step 9: Commit the snapshot unit**

```bash
git add docker/hermes-agent/bootstrap/hermes_bootstrap/profile_snapshot.py \
  docker/hermes-agent/bootstrap/tests/test_profile_snapshot.py
git commit -m "feat: build safe Hermes profile snapshots"
```

---

### Task 2: Mirror Exact Snapshots With Git Plumbing

**Files:**

- Create: `docker/hermes-agent/bootstrap/hermes_bootstrap/profile_sync.py`
- Create: `docker/hermes-agent/bootstrap/tests/test_profile_sync.py`
- Reuse: `docker/hermes-agent/bootstrap/hermes_bootstrap/git.py:192-237,252-333,466-526`
- Reuse: `docker/hermes-agent/bootstrap/hermes_bootstrap/repositories.py:152-275`

**Interfaces:**

- Consumes: `PreparedProfiles`, `ProfileSnapshot`, and `GitAuth`.
- Produces: an aggregate report used unchanged by CLI, bootstrap, cron output, and integration tests.

- [ ] **Step 1: Write failing result and no-change tests**

Define expected output around these types:

```python
SyncStatus = Literal["changed", "unchanged", "failed"]

@dataclass(frozen=True)
class ProfileDiff:
    added: tuple[PurePosixPath, ...] = ()
    modified: tuple[PurePosixPath, ...] = ()
    deleted: tuple[PurePosixPath, ...] = ()

@dataclass(frozen=True)
class ProfileSyncResult:
    name: str
    status: SyncStatus
    commit: str | None
    snapshot: str
    diff: ProfileDiff
    category: str
    message: str

@dataclass(frozen=True)
class ProfileSyncReport:
    dry_run: bool
    profiles: tuple[ProfileSyncResult, ...]
    exit_code: int
```

Implement `ProfileSyncResult.as_dict() -> dict[str, object]` and
`ProfileSyncReport.as_dict() -> dict[str, object]`. The aggregate mapping has
exact keys `schema_version`, `command`, `dry_run`, `status`, and `profiles`;
each profile mapping has exact keys `name`, `status`, `commit`, `snapshot`,
`added`, `modified`, `deleted`, `paths`, `category`, and `message`.
Also implement `failed_profile_report(profiles: tuple[DistributionSource,
...], *, dry_run: bool, category: str, message: str, exit_code: int) ->
ProfileSyncReport` so credential and aggregate-preflight failures still emit one
result for every configured profile.

Test that identical trees return `unchanged`, no commit is created, the snapshot digest is present, and paths appear only as relative allowlisted names.

- [ ] **Step 2: Run `test_profile_sync` and verify RED**

```bash
docker run --rm -v "$PWD/docker/hermes-agent/bootstrap:/workspace/bootstrap:ro" \
  -e PYTHONPATH=/workspace/bootstrap \
  --entrypoint /opt/hermes/.venv/bin/python local/hermes-bootstrap-test \
  -m unittest discover -s /workspace/bootstrap/tests \
  -p 'test_profile_sync.py' -v
```

Expected: import failure for `profile_sync`.

- [ ] **Step 3: Implement one exact-tree attempt without checkout**

Add public callables with exact signatures
`synchronize_prepared_profiles(prepared: PreparedProfiles, auth: GitAuth, *,
dry_run: bool) -> ProfileSyncReport` and
`synchronize_profiles(manifest: BootstrapManifest, auth: GitAuth, *, dry_run:
bool) -> ProfileSyncReport`.

`synchronize_profiles` creates a mode-`0700` scratch directory beneath the
validated data root, calls `prepare_profile_snapshots(..., allow_missing=False)`,
passes the complete prepared set to `synchronize_prepared_profiles`, and removes
the scratch tree on success and failure. A cleanup failure produces a failed
report rather than silently leaving token-adjacent Git state.

For each profile, take `/opt/data/locks/repositories/profile-{name}.lock`, create a mode-`0700` temporary Git directory, create askpass, and run this plumbing sequence through `_run_git_bytes` with bounded output:

```text
git init --quiet
git remote add origin -- "$source"
git config --get remote.origin.url
git fetch --no-tags origin -- "$branch"
git rev-parse --verify FETCH_HEAD^{commit}
git read-tree --empty
copy immutable snapshot into the private worktree
git add -A -- .
git ls-files --stage -z
git write-tree
git rev-parse FETCH_HEAD^{tree}
```

Require the staged path set to equal exactly `.gitignore`, `distribution.yaml`, and `snapshot.entries`; accept only blob modes `100644` and `100755`. Never check out `FETCH_HEAD`, run hooks, read global/system config, or retain remote file content.

- [ ] **Step 4: Write failing change/delete/dry-run tests**

Use a local bare remote to cover local add/modify/delete, deletion of remote-only `.github`, README, tests, and scripts, local replacement of a conflicting owned file, generated `.gitignore`, binary assets, and `--dry-run` leaving the remote ref unchanged.

Assert the dry-run report contains sorted `added`, `modified`, and `deleted` relative paths and no file bytes or fixture tokens.

- [ ] **Step 5: Implement diff, commit, and fast-forward push**

Compare the empty-index projection to `FETCH_HEAD` with `git diff --cached --name-status -z --no-renames FETCH_HEAD`. If the tree differs and `dry_run` is false, create a commit without a checkout:

```text
git -c user.name=Hermes Bootstrap \
    -c user.email=hermes-bootstrap@localhost \
    commit-tree "$tree" -p "$remote_commit" \
    -m "chore: sync Hermes profile $name"
git push --porcelain -- "$source" "$commit:refs/heads/$branch"
```

Validate the configured destination as a branch name before constructing
`refs/heads/{branch}`. Fetch after push and require the remote head or a
same-tree descendant to contain the exact snapshot.

- [ ] **Step 6: Write failing lock, race, cleanup, and redaction tests**

Cover lock contention, hardlinked/replaced lock paths, first and second non-fast-forward rejection, a remote advance with the same tree, askpass cleanup, temporary repository cleanup, output overflow, wrong remote identity, branch-rule push rejection, and exception graphs containing no token or owned file content.

- [ ] **Step 7: Implement one race retry and aggregate continuation**

On first publication mismatch, fetch the new head, reset the index to empty, rebuild the same snapshot tree, and create one new child commit. A second mismatch returns `failed` with category `push_race_exhausted`.

Run profiles sequentially. Catch a profile Git failure into its result and
continue. Use exit code `0` only when no result failed; use repository exit code
`4` otherwise. In `synchronize_profiles`, catch `ProfileSnapshotError` before
calling `synchronize_prepared_profiles`; represent the invalid profile as
`failed` and every unattempted profile as `failed` with category
`aggregate_preflight_blocked`.

- [ ] **Step 8: Run focused tests and verify GREEN**

```bash
docker run --rm -v "$PWD/docker/hermes-agent/bootstrap:/workspace/bootstrap:ro" \
  -e PYTHONPATH=/workspace/bootstrap \
  --entrypoint /opt/hermes/.venv/bin/python local/hermes-bootstrap-test \
  -m unittest discover -s /workspace/bootstrap/tests \
  -p 'test_profile_sync.py' -v
```

Expected: every profile-sync unit test passes, a second sync is `unchanged`, and `git fsck --strict` passes for each bare fixture remote.

- [ ] **Step 9: Commit the Git mirror unit**

```bash
git add docker/hermes-agent/bootstrap/hermes_bootstrap/profile_sync.py \
  docker/hermes-agent/bootstrap/tests/test_profile_sync.py
git commit -m "feat: mirror local Hermes profiles to Git"
```

---

### Task 3: Add The Aggregate CLI And Stable Exit Contract

**Files:**

- Modify: `docker/hermes-agent/bootstrap/hermes_bootstrap/app.py:197-222,295-310`
- Modify: `docker/hermes-agent/bootstrap/hermes_bootstrap/cli.py:21-108`
- Modify: `docker/hermes-agent/bootstrap/tests/test_app.py:394-431`
- Modify: `docker/hermes-agent/bootstrap/tests/test_cli.py:1-174`

**Interfaces:**

- Consumes: `synchronize_profiles(...)`, `_runtime_token(...)`, and `ProfileSyncReport`.
- Produces: `hermes-bootstrap sync-profiles [--dry-run]`, one compact JSON line, and a meaningful process status.

- [ ] **Step 1: Write failing CLI dispatch and JSON tests**

Add tests for:

```python
code, stdout, stderr = self.invoke(["sync-profiles", "--dry-run"])
self.assertEqual(code, 0)
self.assertEqual(json.loads(stdout)["command"], "sync-profiles")
self.assertEqual(stderr, "")
```

Also require a report containing one failed profile to be printed to stdout with exit `4`, invalid arguments to return `2`, and stdin never to be read.

- [ ] **Step 2: Run `test_cli` and `test_app` and verify RED**

```bash
docker run --rm -v "$PWD/docker/hermes-agent/bootstrap:/workspace/bootstrap:ro" \
  -e PYTHONPATH=/workspace/bootstrap \
  --entrypoint /opt/hermes/.venv/bin/python local/hermes-bootstrap-test \
  -m unittest discover -s /workspace/bootstrap/tests \
  -p 'test_cli.py' -v
docker run --rm -v "$PWD/docker/hermes-agent/bootstrap:/workspace/bootstrap:ro" \
  -e PYTHONPATH=/workspace/bootstrap \
  --entrypoint /opt/hermes/.venv/bin/python local/hermes-bootstrap-test \
  -m unittest discover -s /workspace/bootstrap/tests \
  -p 'test_app.py' -v
```

Expected: argparse rejects `sync-profiles` and `app.sync_profiles` is absent.

- [ ] **Step 3: Add the app boundary**

Implement the public command boundary so token failures become a report instead
of stderr-only output:

```python
def sync_profiles(
    manifest_path: Path,
    *,
    dry_run: bool,
    environ: Mapping[str, str] | None = None,
) -> ProfileSyncReport:
    manifest = load_manifest(manifest_path)
    environment = os.environ if environ is None else environ
    try:
        token = _runtime_token(manifest, environment)
        auth = GitAuth(token, SecretRedactor((token,)))
        return profile_sync.synchronize_profiles(manifest, auth, dry_run=dry_run)
    except CredentialError:
        return failed_profile_report(
            manifest.profiles,
            dry_run=dry_run,
            category="credentials_unavailable",
            message="GitHub credentials are unavailable",
            exit_code=CredentialError.exit_code,
        )
    finally:
        if "token" in locals():
            token = None
```

Keep token-bearing locals behind a non-raising boundary like `sync_repository`; sanitize unexpected errors to `CredentialError` or `RepositoryError` without retaining a traceback containing token values.

- [ ] **Step 4: Add an outcome exit code to CLI**

Extend `_CommandOutcome` with `exit_code: int = 0`. Dispatch `sync-profiles` explicitly, write `report.as_dict()` to stdout, and return `report.exit_code` after a successful write. Do not infer command selection through the existing final `else` branch.

Parser contract:

```python
sync_profiles = commands.add_parser("sync-profiles")
sync_profiles.add_argument("--dry-run", action="store_true")
sync_profiles.add_argument("--manifest", default=DEFAULT_MANIFEST, type=_path)
```

- [ ] **Step 5: Verify runtime-token precedence and redaction**

Test process `GH_TOKEN`, active safe `HERMES_HOME/.env`, and root `.env`
precedence; reject unrelated/symlinked runtime homes and unsafe token files
exactly as `sync-repository` does. Confirm missing credentials print all
configured profile names with category `credentials_unavailable`, exit `3`, and
no token. Confirm repository failures print all configured profile names and
exit `4`.

- [ ] **Step 6: Run focused tests and commit**

```bash
docker run --rm -v "$PWD/docker/hermes-agent/bootstrap:/workspace/bootstrap:ro" \
  -e PYTHONPATH=/workspace/bootstrap \
  --entrypoint /opt/hermes/.venv/bin/python local/hermes-bootstrap-test \
  -m unittest discover -s /workspace/bootstrap/tests \
  -p 'test_cli.py' -v
docker run --rm -v "$PWD/docker/hermes-agent/bootstrap:/workspace/bootstrap:ro" \
  -e PYTHONPATH=/workspace/bootstrap \
  --entrypoint /opt/hermes/.venv/bin/python local/hermes-bootstrap-test \
  -m unittest discover -s /workspace/bootstrap/tests \
  -p 'test_app.py' -v
```

Expected: all CLI and app tests pass, both success and failure JSON remain one
line, and no traceback retains the fixture token.

```bash
git add docker/hermes-agent/bootstrap/hermes_bootstrap/app.py \
  docker/hermes-agent/bootstrap/hermes_bootstrap/cli.py \
  docker/hermes-agent/bootstrap/tests/test_app.py \
  docker/hermes-agent/bootstrap/tests/test_cli.py
git commit -m "feat: expose aggregate Hermes profile sync"
```

---

### Task 4: Insert Local-First Sync Into Bootstrap Apply

**Files:**

- Modify: `docker/hermes-agent/bootstrap/hermes_bootstrap/app.py:107-186,254-292`
- Modify: `docker/hermes-agent/bootstrap/tests/test_app.py:167-251,433-468`

**Interfaces:**

- Consumes: `prepare_profile_snapshots(..., allow_missing=True)`, `synchronize_prepared_profiles(...)`, and `stage_distribution(...)`.
- Produces: exact named-profile `StagedSource` objects ordered like `manifest.profiles`, while retaining the current root/shared transaction flow.

- [ ] **Step 1: Write the failing existing-profile order test**

Update the orchestration event assertion to require:

```text
recover
payload
profile-preflight
profile-sync:rick
stage:default
stage:rick:0123456789abcdef0123456789abcdef01234567
sync:lifelog
root
profile:rick
shared:lifelog
env:data
env:rick
validate
commit
```

Assert `Transaction.begin` occurs only after all sync and staging calls.

- [ ] **Step 2: Write failing first-install and failure-boundary tests**

Cover:

- a missing profile is listed in `PreparedProfiles.missing`, staged from its configured branch, and installed through the official Hermes API;
- an existing invalid profile never falls back to remote;
- one failed profile report prevents root/profile/shared apply and `Transaction.begin`;
- earlier successful remote pushes remain represented in the failure report; and
- cleanup removes private snapshots and Git stages without touching local profile bytes.

- [ ] **Step 3: Implement the new apply sequence**

Inside the existing secret boundary:

```python
prepared = prepare_profile_snapshots(manifest, scratch, allow_missing=True)
profile_report = synchronize_prepared_profiles(prepared, auth, dry_run=False)
if profile_report.exit_code != 0:
    failed = ",".join(
        item.name for item in profile_report.profiles if item.status == "failed"
    )
    raise RepositoryError(f"named profile repository sync failed: {failed}")

commit_by_name = {
    item.name: item.commit for item in profile_report.profiles
    if item.commit is not None
}
root_stage = stage_distribution(manifest.root_distribution, scratch, auth)
profile_stages = []
for source in manifest.profiles:
    exact = replace(source, ref=commit_by_name[source.name]) \
        if source.name in commit_by_name else source
    profile_stages.append(stage_distribution(exact, scratch, auth))
```

Keep `StagedSource.declaration.source` as the repository URL so Hermes writes the canonical `source`; only `ref` becomes the exact commit for an existing profile. Preserve manifest order when applying profiles.

- [ ] **Step 4: Make cleanup and result reporting explicit**

Include profile snapshot/Git scratch in `_cleanup_apply_resources`. Add the profile sync summary to successful apply output without paths or content:

```json
"profile_sync": {
  "rick": "changed",
  "hoffman": "unchanged",
  "risarisa": "unchanged"
}
```

- [ ] **Step 5: Run app tests and commit**

```bash
docker run --rm -v "$PWD/docker/hermes-agent/bootstrap:/workspace/bootstrap:ro" \
  -e PYTHONPATH=/workspace/bootstrap \
  --entrypoint /opt/hermes/.venv/bin/python local/hermes-bootstrap-test \
  -m unittest discover -s /workspace/bootstrap/tests \
  -p 'test_app.py' -v
```

Expected: all app tests pass, failure occurs before the transaction, missing
targets still install remotely, and the safe error names only failed profiles.

```bash
git add docker/hermes-agent/bootstrap/hermes_bootstrap/app.py \
  docker/hermes-agent/bootstrap/tests/test_app.py
git commit -m "feat: sync local profiles before bootstrap apply"
```

---

### Task 5: Add Three-Profile Integration And Security Regression Coverage

**Files:**

- Create: `docker/hermes-agent/bootstrap/tests/integration/test_profile_sync_flow.py`
- Modify: `docker/hermes-agent/bootstrap/tests/integration/test_bootstrap_flow.py`
- Modify only if required by test discovery: `docker/hermes-agent/Dockerfile:46-56`

**Interfaces:**

- Consumes: public `cli.main`, `app.apply`, and local bare Git repositories.
- Produces: end-to-end evidence for all three profiles, partial failure, retry, dry-run, bootstrap first install, and local immutability.

- [ ] **Step 1: Build a three-profile bare-remote fixture**

Create `rick`, `hoffman`, and `risarisa` local profile homes and bare remotes. Rick/Hoffman fixtures contain two PNG byte fixtures under `assets`; RisaRisa omits assets. Seed each remote with `.github/workflows/distribution.yml`, validators, README, and stale owned content so exact deletion is observable.

- [ ] **Step 2: Write the aggregate happy-path test**

Assert one real command:

```python
exit_code = cli.main(
    ["sync-profiles", "--manifest", str(self.manifest_path)],
    stdout=stdout,
    stderr=stderr,
    environ={"GH_TOKEN": FIXTURE_TOKEN},
)
```

The test requires `changed` for all three, leaves local tree snapshots
byte-for-byte identical, and leaves each remote tree equal to `.gitignore`,
`distribution.yaml`, and its local owned paths. Its second invocation requires
three `unchanged` results and unchanged remote commit IDs.

- [ ] **Step 3: Run the integration test and verify RED**

```bash
docker run --rm -v "$PWD/docker/hermes-agent/bootstrap:/workspace/bootstrap:ro" \
  -e PYTHONPATH=/workspace/bootstrap \
  --entrypoint /opt/hermes/.venv/bin/python local/hermes-bootstrap-test \
  -m unittest discover -s /workspace/bootstrap/tests/integration \
  -p 'test_profile_sync_flow.py' -v
```

Expected: FAIL because the aggregate Git and bootstrap behavior is not yet
complete in the integration fixture.

- [ ] **Step 4: Add failure and retry scenarios**

Cover invalid RisaRisa preflight causing zero remote ref changes, Hoffman push failure while Rick and RisaRisa are attempted, retry convergence, one simulated remote race, and a second race returning aggregate exit `4`. Assert no remote token or secret marker appears in stdout, stderr, exceptions, or child-process arguments.

- [ ] **Step 5: Add bootstrap scenarios**

Prove missing RisaRisa seeds from remote, invalid existing RisaRisa blocks all pushes, successful existing-profile sync stages the reported commit, and a sync failure leaves runtime sentinels and transaction journals unchanged.

- [ ] **Step 6: Run the full container gate**

```bash
task hermes:bootstrap:test
```

Expected: all bootstrap unit/integration tests pass, `test_gh_wrapper.sh` prints `PASS`, and no test process remains running.

- [ ] **Step 7: Commit the integration coverage**

```bash
git add docker/hermes-agent/bootstrap/tests/integration/test_profile_sync_flow.py \
  docker/hermes-agent/bootstrap/tests/integration/test_bootstrap_flow.py \
  docker/hermes-agent/Dockerfile
git commit -m "test: cover local-first Hermes profile sync"
```

Stage `Dockerfile` only if test discovery actually required a change.

---

### Task 6: Update Dotfiles Operations Documentation

**Files:**

- Modify: `docs/hermes-agent/bootstrap-design.md:27-35,76-101,221-260`
- Modify: `docs/hermes-agent/bootstrap.md:35-50,92-121,151-180`
- Modify: `docs/hermes-agent/profile-home-layout.md:24-48`
- Modify: `docs/hermes-agent/profile-local-authoritative-sync-design.md`

**Interfaces:**

- Consumes: the implemented command and final result schema.
- Produces: one non-contradictory operator story for root, named profiles, and shared repositories.

- [ ] **Step 1: Replace obsolete named-profile authority statements**

State that existing local named profiles are authoritative, profile homes remain non-Git, bootstrap exports exact allowlisted snapshots before applying the same exact commits, and only missing first installs seed from remote. Keep root and lifelog wording unchanged.

- [ ] **Step 2: Document commands and failure recovery**

Add:

```text
docker compose -f docker/hermes-agent/compose.yml run --rm --no-deps -T \
  hermes-bootstrap sync-profiles --dry-run

docker compose -f docker/hermes-agent/compose.yml run --rm --no-deps -T \
  hermes-bootstrap sync-profiles
```

Document statuses, credential exit `3`, repository/preflight exit `4`, aggregate
preflight, one race retry, exact remote deletion, local immutability, and the
first-install exception. Document the repair handoff: assign only the failed
profile and redacted category, fix the local authoritative source or owning
engine/environment, run dry-run, run real sync, and accept the repair only when
the aggregate exits `0` and the repaired profile is `changed` or `unchanged`.

- [ ] **Step 3: Run formatting and the final dotfiles gate**

```bash
pre-commit run --files \
  docs/hermes-agent/bootstrap-design.md \
  docs/hermes-agent/bootstrap.md \
  docs/hermes-agent/profile-home-layout.md \
  docs/hermes-agent/profile-local-authoritative-sync-design.md
task hermes:bootstrap:test
git diff --check
```

Expected: all commands exit `0`.

- [ ] **Step 4: Commit the operations docs**

```bash
git add docs/hermes-agent/bootstrap-design.md \
  docs/hermes-agent/bootstrap.md \
  docs/hermes-agent/profile-home-layout.md \
  docs/hermes-agent/profile-local-authoritative-sync-design.md
git commit -m "docs: explain local-first Hermes profile sync"
```

---

### Task 7: Add The Root Cron Distribution

**Files:**

- Create worktree: `/Users/ktome1995/Program/hermes-home-profile-sync`
- Create: `scripts/profile_sync.sh`
- Modify: `root-distribution.yaml:6-16`
- Modify: `cron/jobs.json:2-88`
- Modify: `scripts/validate_distribution.py:31-57,72-89,189-219`
- Modify: `tests/test_validate_distribution.py:99-140,589-731`

**Interfaces:**

- Consumes: `/usr/local/bin/hermes-bootstrap sync-profiles` from the merged dotfiles engine.
- Produces: root-owned executable wrapper and `profile-local-sync` cron job delivered to `slack:C0BK3UYEP6V`.

- [ ] **Step 1: Create the isolated hermes-home branch**

```bash
git -C /Users/ktome1995/Program/hermes-home fetch origin main
git -C /Users/ktome1995/Program/hermes-home worktree add \
  /Users/ktome1995/Program/hermes-home-profile-sync \
  -b codex/hermes-profile-sync-cron origin/main
cd /Users/ktome1995/Program/hermes-home-profile-sync
```

Expected: clean branch based on current `origin/main`; the existing main checkout remains on `main` and clean.

- [ ] **Step 2: Write failing root validator tests**

Update fixtures and assertions to require:

```python
self.assertEqual(
    (profile_sync["script"], profile_sync["no_agent"], profile_sync["schedule"]["expr"]),
    ("profile_sync.sh", True, "30 */2 * * *"),
)
self.assertEqual(profile_sync["deliver"], delivery)
```

Require exactly three job IDs: `lifelog-core-sync`, `article-news-slack-post`, and `profile-local-sync`. Add `scripts/profile_sync.sh` to exact owned paths and runtime scripts. Require executable mode, `bash -n`, and exact thin-wrapper lines with no `git`, askpass, credential, or token logic.

- [ ] **Step 3: Run fast tests and verify RED**

```bash
python3 -m unittest tests.test_normalize_cron_delivery \
  tests.test_validate_distribution -v
```

Expected: failures for the absent owned script and third cron job.

- [ ] **Step 4: Add the thin wrapper and root ownership**

Create executable `scripts/profile_sync.sh` with exactly:

```bash
#!/usr/bin/env bash
set -euo pipefail

exec /usr/local/bin/hermes-bootstrap sync-profiles
```

Add `scripts/profile_sync.sh` to `root-distribution.yaml`, `EXPECTED_OWNED_PATHS`, `RUNTIME_SCRIPTS`, and the embedded manifest contract in `validate_distribution.py`.

- [ ] **Step 5: Add the two-hour cron job**

Append a no-agent job to `cron/jobs.json` with:

```json
{
  "id": "profile-local-sync",
  "name": "Hermes named profile GitHub sync",
  "prompt": "Mirror each local named profile's declared distribution-owned files to its configured GitHub repository.",
  "skills": [],
  "skill": null,
  "model": null,
  "provider": null,
  "provider_snapshot": null,
  "model_snapshot": null,
  "base_url": null,
  "script": "profile_sync.sh",
  "no_agent": true,
  "context_from": null,
  "schedule": { "kind": "cron", "expr": "30 */2 * * *", "display": "30 */2 * * *" },
  "schedule_display": "30 */2 * * *",
  "repeat": { "times": null, "completed": 0 },
  "enabled": true,
  "state": "scheduled",
  "paused_at": null,
  "paused_reason": null,
  "last_run_at": null,
  "last_status": null,
  "last_error": null,
  "last_delivery_error": null,
  "enabled_toolsets": ["terminal"],
  "workdir": null,
  "fire_claim": null,
  "deliver": "slack:C0BK3UYEP6V"
}
```

Keep the current lifelog and article jobs unchanged. Run `python3 scripts/normalize_cron_delivery.py` so all three jobs use the canonical policy.

- [ ] **Step 6: Run fast and full local validation**

```bash
python3 -m unittest tests.test_normalize_cron_delivery \
  tests.test_validate_distribution -v
python3 scripts/validate_distribution.py fast --json
python3 scripts/validate_distribution.py full --json
pre-commit run --all-files --hook-stage pre-commit
pre-commit run --all-files --hook-stage pre-push
```

Expected: tests pass; fast and full report `status: pass`; both hook stages are installed and no generated report is tracked.

- [ ] **Step 7: Commit the root cron distribution**

```bash
git add root-distribution.yaml cron/jobs.json scripts/profile_sync.sh \
  scripts/validate_distribution.py tests/test_validate_distribution.py
git commit -m "feat: schedule Hermes profile repository sync"
```

---

### Task 8: Publish And Merge In Dependency Order

**Files:** None beyond the committed branches.

**Interfaces:**

- Consumes: exact-head local validation from Tasks 5-7.
- Produces: merged dotfiles engine first, then merged `hermes-home` cron distribution.

- [ ] **Step 1: Re-run and record exact-head dotfiles evidence**

```bash
cd /Users/ktome1995/Program/dotfiles-hermes-profile-sync
task hermes:bootstrap:test
pre-commit run --all-files
git status --short
git rev-parse HEAD
```

Expected: tests and hooks exit `0`; status is clean; record the exact SHA.

- [ ] **Step 2: Push the dotfiles branch and create a PR**

```bash
git push -u origin codex/hermes-profile-local-sync
gh pr create --base main --head codex/hermes-profile-local-sync \
  --title "feat: sync Hermes profiles from local state" \
  --body $'## Summary\n- make installed named profiles authoritative\n- mirror only generated allowlist content\n- sync before bootstrap apply and expose dry-run\n\n## Validation\n- task hermes:bootstrap:test\n- pre-commit run --all-files'
gh pr checks --watch
```

The PR body must state local authority, exact deletions, secret boundary, first-install exception, cron dependency, and exact test evidence. Do not merge on an unknown/missing check. If GitHub explicitly reports billing exhaustion, classify it using `distribution-validation-design.md` and obtain the same explicit user approval required by that fallback.

- [ ] **Step 3: Merge dotfiles and verify remote main**

```bash
gh pr merge --merge --delete-branch
gh pr view --json state,mergedAt,mergeCommit
git fetch origin main
git merge-base --is-ancestor HEAD origin/main
```

Expected: PR state `MERGED` and the feature head is an ancestor of `origin/main`.

- [ ] **Step 4: Re-run and record exact-head hermes-home evidence**

```bash
cd /Users/ktome1995/Program/hermes-home-profile-sync
python3 scripts/validate_distribution.py full --json
pre-commit run --all-files --hook-stage pre-commit
pre-commit run --all-files --hook-stage pre-push
git status --short
git rev-parse HEAD
```

Expected: full validation passes and worktree is clean.

- [ ] **Step 5: Push, review, and merge hermes-home**

```bash
git push -u origin codex/hermes-profile-sync-cron
gh pr create --base main --head codex/hermes-profile-sync-cron \
  --title "feat: schedule Hermes profile repository sync" \
  --body $'## Summary\n- add the profile sync runtime wrapper\n- schedule it every two hours at minute 30\n- deliver every result to hermes-cron-results\n\n## Validation\n- python3 scripts/validate_distribution.py full --json\n- pre-commit run --all-files --hook-stage pre-commit\n- pre-commit run --all-files --hook-stage pre-push'
gh pr checks --watch
gh pr merge --merge --delete-branch
gh pr view --json state,mergedAt,mergeCommit
```

Do not merge `hermes-home` until dotfiles main contains `sync-profiles`. Use the same explicit billing-fallback classifier rather than treating an absent workflow run as success.

---

### Task 9: Perform Guarded Production Rollout And Slack Acceptance

**Files:** Runtime state and the four profile remote repositories only; no direct source edits.

**Interfaces:**

- Consumes: merged dotfiles image, merged root distribution, installed local profile homes, and root `.env` GitHub credentials.
- Produces: exact remote profile mirrors, installed two-hour cron, and verified Slack delivery.

- [ ] **Step 1: Build the merged engine without applying bootstrap**

From a clean checkout of merged dotfiles main:

```bash
docker compose -f docker/hermes-agent/compose.yml build hermes hermes-bootstrap
docker compose -f docker/hermes-agent/compose.yml config --quiet
```

Expected: build and Compose validation pass. Do not run `task hermes:bootstrap` yet because apply performs a real profile sync.

- [ ] **Step 2: Inspect branch rules before mutation**

```bash
for repo in hermes-profile-rick hermes-profile-hoffman hermes-profile-risarisa hermes-profile-nancy; do
  gh api "repos/rurusasu/$repo/branches/main/protection" || \
    printf '%s\n' "$repo: no classic branch protection response"
  gh api "repos/rurusasu/$repo/rulesets" --jq '.[] | [.id,.name,.enforcement] | @tsv'
done
```

Classify `404` as no classic protection response; inspect rulesets in the same
loop with `gh api "repos/rurusasu/$repo/rulesets"`. Do not weaken a rule
silently. A rule requiring PRs or branch-hosted workflows must be reconciled
explicitly because unattended exact-mirror push cannot bypass it.

- [ ] **Step 3: Run and inspect the production dry run**

```bash
docker compose -f docker/hermes-agent/compose.yml run --rm --no-deps -T \
  hermes-bootstrap sync-profiles --dry-run
```

Expected: one JSON report covering Rick, Hoffman, RisaRisa, and Nancy; snapshot digests are present; planned trees contain only `.gitignore`, `distribution.yaml`, and locally owned paths; Rick/Hoffman/Nancy include both images; RisaRisa has no undeclared assets; no local file changes occur.

- [ ] **Step 4: Run the real sync and prove idempotence**

After reviewing every planned deletion:

```bash
docker compose -f docker/hermes-agent/compose.yml run --rm --no-deps -T \
  hermes-bootstrap sync-profiles
docker compose -f docker/hermes-agent/compose.yml run --rm --no-deps -T \
  hermes-bootstrap sync-profiles --dry-run
```

Expected: first command reports `changed` or `unchanged`; second reports all `unchanged` with the same local snapshot digests.

- [ ] **Step 5: Verify exact remote trees**

```bash
for repo in hermes-profile-rick hermes-profile-hoffman hermes-profile-risarisa hermes-profile-nancy; do
  gh api "repos/rurusasu/$repo/git/trees/main?recursive=1" \
    --jq '.tree[] | [.type,.path] | @tsv'
done
```

Compare each path list to its dry-run allowlist. Confirm `.github`, validators, tests, README files, runtime state, and secrets are absent. Confirm the local snapshot digest still matches Step 3.

- [ ] **Step 6: Apply merged root cron distribution**

```bash
task hermes:bootstrap
docker compose -f docker/hermes-agent/compose.yml exec -T hermes hermes cron list
```

Expected: bootstrap reports profile sync `unchanged`, the stack restarts only after success, and `profile-local-sync` is active at `30 */2 * * *` with delivery `slack:C0BK3UYEP6V`.

- [ ] **Step 7: Trigger one manual cron execution**

```bash
docker compose -f docker/hermes-agent/compose.yml exec -T hermes \
  hermes cron run --accept-hooks profile-local-sync
docker compose -f docker/hermes-agent/compose.yml exec -T hermes \
  hermes cron tick --accept-hooks
docker compose -f docker/hermes-agent/compose.yml exec -T hermes \
  hermes cron runs --limit 5 profile-local-sync
```

Expected: latest durable attempt is `completed`, wrapper exit is `0`, and output contains only profile statuses, counts, commits, and snapshot digests.

- [ ] **Step 8: Verify Slack and the next scheduled run**

Open the private `hermes-cron-results` channel and verify a message for `profile-local-sync` contains Rick, Hoffman, RisaRisa, and Nancy as `unchanged` or `changed`, with no credentials or file contents. Record the next UTC run from `hermes cron list`; `30 */2 * * *` corresponds to odd-hour `:30` runs in JST. After that time, verify a second successful Slack message and no new profile commits for an all-unchanged run.

- [ ] **Step 9: Close with final repository and runtime evidence**

Report both merged PR URLs and SHAs, the four remote heads, unchanged local snapshot digests for Rick, Hoffman, RisaRisa, and Nancy, cron schedule, durable run ID/status, and Slack message timestamp. Any failed profile, missing Slack post, changed local digest, or unexpected remote path leaves rollout incomplete.
