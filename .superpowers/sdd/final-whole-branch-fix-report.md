# Final Whole-Branch Fix Report

Date: 2026-07-23

## Outcome

Status: `DONE_WITH_CONCERNS`

- Dotfiles worktree: `/Users/ktome1995/Program/dotfiles-hermes-profile-sync`
- Branch: `codex/hermes-profile-local-sync`
- Starting commit: `906e3053ad5ea18ae553b2717b3e9737b48611c2`
- Implementation commit: `1ca84f85e8d0d726c0bf02c47ee784b16f308b98`
- Hermes-home worktree: `/Users/ktome1995/Program/hermes-home-profile-sync`
- Branch: `codex/hermes-profile-sync-cron`
- Verified commit: `a2b82933e415444e04f845f3afb5a0369d52ed4f`
- Hermes-home source changes: none
- Pushes, pull requests, merges, and main-checkout changes: none

The repository `task commit` wrapper was not used because it hardcodes
`~/.dotfiles` for format, lint, staging, and commit. Direct worktree-local Git
commits were required to preserve the explicit prohibition on touching the main
checkout. The equivalent required formatting, test, and hook gates were run in
the dedicated worktree before committing.

## Finding Resolution

### Important 1: Replacement-safe cleanup

Added the shared `PrivateDirectory` cleanup primitive in
`filesystem.py`. Creation retains parent and directory descriptors plus the
expected device and inode. Cleanup:

- revalidates the absolute parent and the captured identity;
- recursively removes entries through directory descriptors;
- never follows symlinks;
- rejects cross-device descendants;
- uses no-replace quarantine renames and inode revalidation;
- fails closed when a mutable pathname is replaced;
- never deletes the replacement tree;
- removes the originally captured private tree through its retained identity;
- returns failure so the existing redacted `cleanup_failed` or apply cleanup
  boundary wins.

The primitive now owns outer bootstrap scratch, aggregate profile snapshot
scratch, per-profile Git scratch, and private shared-repository staging or
publication copies. No private-stage pathname-only `shutil.rmtree` fallback was
added.

Deterministic replacement checkpoints cover all four required stages. Each test
asserts that the replacement survives, the retired original tree is removed,
and cleanup failure is surfaced through the redacted boundary.

### Important 2: Empty owned directories

Aggregate snapshot preflight now raises:

```text
ProfileSnapshotError(<profile>, "empty_owned_directory")
```

for every declared owned directory that has no publishable regular-file
descendant. It does not synthesize a placeholder.

The unit test proves the precise category and clean scratch removal. The
integration ordering test proves the failure happens before:

- any profile `_push_commit`;
- shared-repository `synchronize_remote`;
- `Transaction.begin`;
- local-byte mutation.

It also proves all remote heads and the local tree remain byte-for-byte
unchanged and temporary scratch is clean.

### Minor 3: Nancy in Task 9

Task 9 now includes Nancy alongside Rick, Hoffman, and RisaRisa in:

- repository scope and branch-rule checks;
- dry-run and real remote verification;
- expected image ownership;
- Slack acceptance;
- final remote-head and snapshot-digest evidence.

### Minor 4: Executable cross-repository contract

The dotfiles suite contains an executable, mode-preserving copy of the exact
hermes-home wrapper plus provenance:

```text
source commit: a2b82933e415444e04f845f3afb5a0369d52ed4f
Git blob SHA-1: 16522f5a8a1fef7c74305203c04e9c44b137f767
SHA-256: 402d1246b7f94cc9349cbbeae5dd4177206ea69a1f5619de8c975c840dfd7317
```

The CI-suitable test executes both the wrapper and the real built
`/usr/local/bin/hermes-bootstrap sync-profiles` entrypoint with an offline,
credential-free environment. It asserts identical stdout, stderr, and exit
status, plus the exact `rick`, `hoffman`, `risarisa`, `nancy` route.

The current real hermes-home wrapper was also mounted into the built dotfiles
image and executed, rather than relying only on the committed artifact:

```text
direct_status=3 wrapped_status=3
command=sync-profiles
profiles=rick,hoffman,risarisa,nancy
categories=credentials_unavailable,credentials_unavailable,credentials_unavailable,credentials_unavailable
```

## TDD Evidence

### RED: focused replacement and empty-directory tests

The new tests were first run against the pre-fix engine:

```bash
docker run --rm \
  -e PYTHONPATH=/usr/local/lib/hermes-bootstrap \
  --entrypoint /opt/hermes/.venv/bin/python \
  local/hermes-bootstrap-red -m unittest -v \
  test_profile_snapshot.ProfileSnapshotTests.test_rejects_an_owned_directory_without_publishable_files \
  test_profile_sync.ProfileSyncTests.test_snapshot_scratch_replacement_is_preserved_and_fails_cleanup \
  test_profile_sync.ProfileSyncTests.test_git_scratch_replacement_is_preserved_and_fails_cleanup \
  test_app.AppTests.test_outer_scratch_replacement_is_preserved_and_fails_cleanup \
  test_repositories.RepositoryTests.test_private_stage_replacement_is_preserved_and_fails_cleanup
```

Result:

```text
Ran 5 tests
FAILED (failures=4, errors=1)
```

Observed failures:

- empty owned directory: expected `ProfileSnapshotError` was not raised;
- snapshot replacement: `invalid_local_profile` instead of `cleanup_failed`;
- Git replacement: `repository` instead of `cleanup_failed`;
- outer replacement: profile-preflight `RepositoryError` instead of cleanup
  `ApplyError`;
- shared stage replacement: generic synchronization failure instead of cleanup
  failure.

### RED: apply ordering

```bash
docker run --rm \
  -e PYTHONPATH=/usr/local/lib/hermes-bootstrap \
  --entrypoint /opt/hermes/.venv/bin/python \
  local/hermes-bootstrap-red -m unittest -v \
  integration.test_profile_sync_flow.ProfileSyncFlowTests.test_empty_owned_directory_blocks_all_apply_side_effects
```

Result:

```text
Ran 1 test
FAILED (errors=1)
```

The old engine reached local apply and raised
`ApplyError: could not apply the named profile distribution`; it did not stop
at aggregate snapshot preflight.

### GREEN: focused tests

The five focused unit tests above:

```text
Ran 5 tests
OK
```

After strengthening the race assertions, the four deterministic replacement
tests were rerun:

```text
Ran 4 tests
OK
```

The ordering integration test:

```text
Ran 1 test
OK
```

The executable wrapper contract:

```text
Ran 1 test
OK
```

## Required Verification

### Dotfiles

```bash
task hermes:bootstrap:test
```

Result: exit `0`; `hermes-bootstrap-test` built successfully and
`test_gh_wrapper: PASS`.

Fresh execution of the built Python test image:

```bash
docker run --rm \
  -e PYTHONPATH=/usr/local/lib/hermes-bootstrap \
  --entrypoint /opt/hermes/.venv/bin/python \
  local/hermes-bootstrap-test \
  -m unittest discover \
  -s /workspace/docker/hermes-agent/bootstrap/tests -v
```

Result:

```text
Ran 455 tests in 40.918s
OK (skipped=1)
```

The single skip is the existing host-resolved Compose contract when no
host-resolved Compose configuration is supplied.

One diagnostic invocation omitted the required `PYTHONPATH` and produced 15
import errors by resolving upstream `/opt/hermes/hermes_bootstrap.py`. The
corrected command above uses the Dockerfile test-stage environment and passed
all 455 tests; this was a command setup error, not a product failure.

```bash
pre-commit run --all-files
```

Result: exit `0`.

```text
fix utf-8 byte order marker: Passed
treefmt: Passed
powershell tests: Passed
chezmoi template lint: Passed
hermes bootstrap container tests: Passed
```

### Hermes-home

```bash
python3 -m unittest discover -s tests -v
```

Result: `Ran 54 tests in 22.233s`, `OK`.

```bash
python3 scripts/validate_distribution.py fast --json
python3 scripts/validate_distribution.py full --json
```

Result: both returned status `pass`, exit `0`.

```bash
pre-commit run --all-files --hook-stage pre-commit
pre-commit run --all-files --hook-stage pre-push
```

Result: normalization and fast validation passed at pre-commit; full
validation passed at pre-push.

### Live wrapper pairing

```bash
actual=/Users/ktome1995/Program/hermes-home-profile-sync/scripts/profile_sync.sh
fixture=docker/hermes-agent/bootstrap/tests/fixtures/hermes-home/profile_sync.sh
cmp "$actual" "$fixture"
git hash-object --no-filters "$actual"
git hash-object --no-filters "$fixture"
shasum -a 256 "$actual"
docker run --rm \
  -v "$actual:/contract/profile_sync.sh:ro" \
  --entrypoint /bin/bash \
  local/hermes-bootstrap-test -c '
    set -u
    export HOME=/nonexistent LANG=C LC_ALL=C
    export PATH=/usr/local/bin:/usr/bin:/bin
    set +e
    /usr/local/bin/hermes-bootstrap sync-profiles \
      >/tmp/direct.out 2>/tmp/direct.err
    direct_status=$?
    /contract/profile_sync.sh >/tmp/wrapped.out 2>/tmp/wrapped.err
    wrapped_status=$?
    set -e
    cmp /tmp/direct.out /tmp/wrapped.out
    cmp /tmp/direct.err /tmp/wrapped.err
    test "$direct_status" -eq 3
    test "$wrapped_status" -eq "$direct_status"
  '
```

Result: `cmp` passed; both Git blob hashes were
`16522f5a8a1fef7c74305203c04e9c44b137f767`; SHA-256 was
`402d1246b7f94cc9349cbbeae5dd4177206ea69a1f5619de8c975c840dfd7317`;
direct and wrapped execution both returned `3` with identical output.

## Owned Files

Dotfiles:

- `docker/hermes-agent/bootstrap/hermes_bootstrap/app.py`
- `docker/hermes-agent/bootstrap/hermes_bootstrap/filesystem.py`
- `docker/hermes-agent/bootstrap/hermes_bootstrap/profile_snapshot.py`
- `docker/hermes-agent/bootstrap/hermes_bootstrap/profile_sync.py`
- `docker/hermes-agent/bootstrap/hermes_bootstrap/repositories.py`
- `docker/hermes-agent/bootstrap/tests/fixtures/hermes-home/profile_sync.provenance.json`
- `docker/hermes-agent/bootstrap/tests/fixtures/hermes-home/profile_sync.sh`
- `docker/hermes-agent/bootstrap/tests/integration/test_hermes_home_wrapper_contract.py`
- `docker/hermes-agent/bootstrap/tests/integration/test_profile_sync_flow.py`
- `docker/hermes-agent/bootstrap/tests/test_app.py`
- `docker/hermes-agent/bootstrap/tests/test_profile_snapshot.py`
- `docker/hermes-agent/bootstrap/tests/test_profile_sync.py`
- `docker/hermes-agent/bootstrap/tests/test_repositories.py`
- `docs/hermes-agent/plans/2026-07-23-hermes-profile-local-sync.md`
- `.superpowers/sdd/final-whole-branch-fix-report.md`

Hermes-home: none.

## Residual Concern

A genuinely live cross-repository checkout is not available to ordinary
single-repository CI. The durable dotfiles CI contract therefore executes an
exact, executable, provenance-pinned hermes-home artifact. Drift changes its
blob or SHA-256 and requires a deliberate fixture update. For final
adjudication, the current two dedicated worktrees were additionally compared
byte-for-byte and the actual hermes-home wrapper was executed successfully
against the built dotfiles engine offline.
