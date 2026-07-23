# Hermes Profile Sync Operation Lock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Serialize mutating Hermes bootstrap operations, reject
post-publication local-profile drift without overwriting local authority, and
replace the unsupported adversarial cleanup claim with a bounded fail-closed
cleanup contract.

**Architecture:** A descriptor-anchored `EngineLock` wraps every mutating public
app entrypoint from before recovery or scratch creation through final cleanup.
`apply` rebuilds and compares local profile snapshots immediately before
`Transaction.begin`, while named-profile apply refuses to replace any existing
target that differs from the staged local projection. Private cleanup uses a
simple two-pass no-follow traversal under the engine lock, explicit terminal
states, mount-ID checks, and no Linux `renameat2` quarantine loop.

**Tech Stack:** Python 3 standard library, `fcntl.flock`, descriptor-relative
filesystem APIs, `unittest`, Docker Compose, Git, pre-commit.

## Global Constraints

- `/opt/data/profiles/<name>` remains authoritative for every existing named
  profile.
- A truly missing profile may be installed from its configured exact remote
  commit; an existing target is never repaired or force-replaced from remote
  bytes.
- The canonical operation lock is
  `/opt/data/locks/bootstrap-engine.lock`.
- `apply`, `sync-profiles`, and `sync-repository` acquire the operation lock
  nonblockingly before recovery or scratch creation and release it only after
  all transaction and private-artifact cleanup.
- `secret-plan` and `validate` remain read-only and do not acquire the operation
  lock.
- Local drift is compared by missing/existing set, canonical manifest bytes,
  generated `.gitignore` bytes, path inventory, mode, size, file SHA-256, and
  aggregate digest.
- Local drift fails as redacted category `local_profile_changed` before
  `Transaction.begin`.
- Remote pushes completed from the original immutable snapshot are not rolled
  back.
- Cleanup does not claim protection against an actively malicious process with
  the same privileges that bypasses the engine lock.
- Cleanup retains no-follow traversal, identity validation, mount/device
  rejection, bounded handling, redacted failures, and explicit terminal state.
- Do not introduce a host UID mapping, privileged helper, or host-OS-specific
  command.
- Do not commit directly to `main`; all changes stay on
  `codex/hermes-profile-local-sync`.

---

### Task 1: Serialize Mutating Bootstrap Commands

**Files:**
- Create:
  `docker/hermes-agent/bootstrap/hermes_bootstrap/engine_lock.py`
- Create:
  `docker/hermes-agent/bootstrap/tests/test_engine_lock.py`
- Modify:
  `docker/hermes-agent/bootstrap/hermes_bootstrap/app.py`
- Modify:
  `docker/hermes-agent/bootstrap/tests/test_app.py`

**Interfaces:**
- Produces:
  `EngineLock.acquire(data_root: Path) -> EngineLock`
- Produces:
  `EngineLock.require_held() -> None`
- Produces:
  `EngineLock.close() -> None`
- Consumes the existing redacted `RepositoryError` boundary.

- [ ] **Step 1: Add failing lock safety and contention tests**

Create `test_engine_lock.py` with cases that:

```python
lock = EngineLock.acquire(data_root)
self.addCleanup(lock.close)
self.assertEqual(
    lock.path,
    data_root / "locks" / "bootstrap-engine.lock",
)
lock.require_held()
with self.assertRaises(RepositoryError):
    EngineLock.acquire(data_root)
```

Also reject a symlink, directory, FIFO, hard link, mode other than `0600`, and
replaced lock parent without modifying the external target. Use a subprocess to
prove cross-process contention and prove a closed lock can be acquired again.

- [ ] **Step 2: Run the new tests and verify RED**

Run:

```bash
cd docker/hermes-agent/bootstrap
PYTHONPATH=. python3 -m unittest tests.test_engine_lock -v
```

Expected: FAIL because `hermes_bootstrap.engine_lock` does not exist.

- [ ] **Step 3: Implement the descriptor-anchored engine lock**

Implement `EngineLock.acquire(data_root: Path) -> EngineLock`,
`require_held() -> None`, `close() -> None`, `__enter__() -> EngineLock`, and
`__exit__(kind: object, value: object, traceback: object) -> None`.

Open canonical `/opt/data` and `locks` with the existing no-follow absolute
directory helper. Create or open only a regular, owner-matching, single-link,
mode-`0600` file. Compare path and descriptor device/inode before and after
`fcntl.flock(descriptor, LOCK_EX | LOCK_NB)`. On contention or unsafe state, close all
descriptors and raise `RepositoryError("bootstrap engine lock is unavailable")`
without exposing external paths or inode details.

- [ ] **Step 4: Add failing app-boundary ordering tests**

In `test_app.py`, patch `EngineLock.acquire`, recovery, scratch creation, sync,
transaction begin, rollback/commit, and cleanup to record events. Require these
orderings:

```text
apply:
lock-acquire < recovery < scratch < transaction-begin < cleanup < lock-close

sync-profiles:
lock-acquire < snapshot-scratch < publication < cleanup < lock-close

sync-repository:
lock-acquire < repository-sync < repository-cleanup < lock-close
```

Also prove `secret-plan` and `validate` never call `EngineLock.acquire`, and
prove lock contention causes no recovery, scratch creation, Git operation, or
transaction.

- [ ] **Step 5: Wrap the public mutating app entrypoints**

For `apply`, use this ordering:

```python
manifest = load_manifest(manifest_path)
with EngineLock.acquire(manifest.data_root) as engine_lock:
    engine_lock.require_held()
    Transaction.recover_if_needed(manifest.data_root)
    outcome = _apply_sensitive_boundary(manifest_path, manifest, input_stream)
```

Keep the lock outside the sensitive boundary so final scratch cleanup completes
before `__exit__`. In `_sync_profiles_boundary`, acquire the lock inside its
existing `try` before `_runtime_token` so contention becomes the existing
aggregate `repository` JSON failure. In `_sync_repository_boundary`, acquire it
inside that function's `try` before `_runtime_token` so its existing
`BootstrapError` boundary is preserved. Do not add nested engine locks in
repository or profile modules.

- [ ] **Step 6: Run focused lock and app tests**

Run:

```bash
cd docker/hermes-agent/bootstrap
PYTHONPATH=. python3 -m unittest \
  tests.test_engine_lock \
  tests.test_app -v
```

Expected: PASS with no skipped lock-ordering case.

- [ ] **Step 7: Commit Task 1**

Run:

```bash
git add \
  docker/hermes-agent/bootstrap/hermes_bootstrap/engine_lock.py \
  docker/hermes-agent/bootstrap/hermes_bootstrap/app.py \
  docker/hermes-agent/bootstrap/tests/test_engine_lock.py \
  docker/hermes-agent/bootstrap/tests/test_app.py
git commit -m "feat: serialize Hermes bootstrap mutations"
```

---

### Task 2: Reject Local Drift Without Overwriting Existing Profiles

**Files:**
- Modify:
  `docker/hermes-agent/bootstrap/hermes_bootstrap/profile_snapshot.py`
- Modify:
  `docker/hermes-agent/bootstrap/hermes_bootstrap/app.py`
- Modify:
  `docker/hermes-agent/bootstrap/hermes_bootstrap/distributions.py`
- Modify:
  `docker/hermes-agent/bootstrap/tests/test_profile_snapshot.py`
- Modify:
  `docker/hermes-agent/bootstrap/tests/test_app.py`
- Modify:
  `docker/hermes-agent/bootstrap/tests/test_distributions.py`
- Modify:
  `docker/hermes-agent/bootstrap/tests/integration/test_profile_sync_flow.py`

**Interfaces:**
- Produces:
  `revalidate_profile_snapshots(manifest: BootstrapManifest, baseline:
  PreparedProfiles, scratch_parent: Path) -> None`
- Extends:
  `apply_profile_distribution(stage, data_root, tx, *,
  replace_existing: bool = True) -> ChangeSet`
- Consumes Task 1's held operation window.

- [ ] **Step 1: Add failing snapshot-comparison tests**

In `test_profile_snapshot.py`, prepare a baseline, then exercise each mutation
before calling `revalidate_profile_snapshots`:

```text
canonical manifest edit
owned file same-size content edit with restored mtime
owned file mode change
owned file addition
owned file deletion
owned file rename
owned directory replacement
previously missing target creation
previously existing target deletion
```

Every case must raise:

```python
with self.assertRaises(ProfileSnapshotError) as caught:
    revalidate_profile_snapshots(manifest, baseline, scratch_parent)
self.assertEqual(caught.exception.category, "local_profile_changed")
```

An unchanged profile set must pass and must remove its comparison scratch.
Injected comparison-scratch cleanup failure must surface as
`ProfileSnapshotError(profile, "cleanup_failed")`.

- [ ] **Step 2: Run the snapshot tests and verify RED**

Run:

```bash
cd docker/hermes-agent/bootstrap
PYTHONPATH=. python3 -m unittest tests.test_profile_snapshot -v
```

Expected: FAIL because `revalidate_profile_snapshots` is absent.

- [ ] **Step 3: Implement complete fingerprint revalidation**

Build a fresh `PreparedProfiles` with `allow_missing=True` in a private child
scratch. Compare this path-independent fingerprint:

```python
def _prepared_fingerprint(
    prepared: PreparedProfiles,
) -> object:
    return (
        tuple(
            (
                snapshot.declaration.name,
                snapshot.manifest_bytes,
                snapshot.gitignore_bytes,
                snapshot.entries,
                snapshot.digest,
            )
            for snapshot in prepared.snapshots
        ),
        tuple(source.name for source in prepared.missing),
    )
```

If fingerprints differ, choose the first mismatching manifest-order profile and
raise `ProfileSnapshotError(name, "local_profile_changed")`. Always clean the
comparison scratch. A cleanup failure overrides an unchanged or drift result
with category `cleanup_failed`.

- [ ] **Step 4: Add failing apply-order and byte-preservation tests**

In `test_app.py` and the integration flow, mutate local state at the following
checkpoints:

```text
after profile publication
after distribution staging
after staged Chrome validation
after shared remote synchronization
```

For an existing profile edit and a previously missing target creation, assert:

```text
remote publication from the first snapshot may remain
Transaction.begin is never called
apply_profile_distribution is never called
local bytes and modes are unchanged by bootstrap
the public failure is redacted
the internal category is local_profile_changed
```

- [ ] **Step 5: Call revalidation immediately before the transaction**

In `_apply_sensitive`, call:

```python
revalidate_profile_snapshots(
    manifest,
    prepared,
    scratch.path,
)
tx = Transaction.begin(manifest.data_root)
```

The call must remain after shared remote synchronization and immediately before
`Transaction.begin`.

- [ ] **Step 6: Add failing final no-overwrite tests**

In `test_distributions.py`, test:

```python
apply_profile_distribution(
    stage,
    data_root,
    tx,
    replace_existing=False,
)
```

Require a missing target to install successfully, a byte-identical existing
target to return `ChangeSet(())`, and any differing or malformed existing target
to raise `ApplyError` without snapshots, deletion, or a call to
`profile_distribution.install_distribution`.

Add a checkpoint that creates the missing target after revalidation but before
profile apply. The new local target must survive byte-for-byte and apply must
fail.

- [ ] **Step 7: Implement the named-profile no-overwrite policy**

Extend the boundary with a keyword:

```python
def apply_profile_distribution(
    stage: StagedSource,
    data_root: Path,
    tx: Transaction,
    *,
    replace_existing: bool = True,
) -> ChangeSet:
    result = _apply_profile_boundary(
        stage,
        data_root,
        tx,
        replace_existing=replace_existing,
    )
    if isinstance(result, _Failure):
        raise ApplyError(result.message)
    return result
```

Inside `_apply_profile_boundary`, compute target existence before deciding to
install. If
`_profile_is_current(target, sanitized, manifest, stage, owned, prior)` is true,
return no changes. If the target
exists and `replace_existing` is false, fail before transaction snapshots,
stale-path removal, environment mutation, or Hermes installation. Only a still
missing target may reach
`profile_distribution.install_distribution(str(sanitized), name=stage.declaration.name, force=True)`.

Pass `replace_existing=False` from `_apply_sensitive`. Keep the default `True`
for the lower-level compatibility tests that explicitly exercise
remote-authoritative distribution replacement.

- [ ] **Step 8: Run focused and integration tests**

Run:

```bash
cd docker/hermes-agent/bootstrap
PYTHONPATH=. python3 -m unittest \
  tests.test_profile_snapshot \
  tests.test_distributions \
  tests.test_app \
  tests.integration.test_profile_sync_flow -v
```

Expected: PASS. Drift cases must show zero transaction and zero local mutation.

- [ ] **Step 9: Commit Task 2**

Run:

```bash
git add \
  docker/hermes-agent/bootstrap/hermes_bootstrap/profile_snapshot.py \
  docker/hermes-agent/bootstrap/hermes_bootstrap/app.py \
  docker/hermes-agent/bootstrap/hermes_bootstrap/distributions.py \
  docker/hermes-agent/bootstrap/tests/test_profile_snapshot.py \
  docker/hermes-agent/bootstrap/tests/test_app.py \
  docker/hermes-agent/bootstrap/tests/test_distributions.py \
  docker/hermes-agent/bootstrap/tests/integration/test_profile_sync_flow.py
git commit -m "fix: preserve local profile authority during apply"
```

---

### Task 3: Simplify Private Scratch Cleanup

**Files:**
- Modify:
  `docker/hermes-agent/bootstrap/hermes_bootstrap/filesystem.py`
- Modify:
  `docker/hermes-agent/bootstrap/tests/test_filesystem.py`
- Modify:
  `docker/hermes-agent/bootstrap/tests/test_app.py`
- Modify:
  `docker/hermes-agent/bootstrap/tests/test_profile_sync.py`
- Modify:
  `docker/hermes-agent/bootstrap/tests/test_repositories.py`

**Interfaces:**
- Preserves:
  `create_private_directory(parent: Path, *, prefix: str) -> PrivateDirectory`
- Preserves:
  `PrivateDirectory.cleanup() -> bool`
- Preserves:
  `PrivateDirectory.release() -> None`
- Adds explicit internal state:
  `_PrivateDirectoryState.ACTIVE`, `CLEANED`, `RELEASED`, and `FAILED`.

- [ ] **Step 1: Replace adversarial race expectations with contract tests**

Delete tests whose only assertion is that repeated quarantine renames defeat an
actively mutating same-privilege attacker. Add focused tests for:

```text
normal nested regular-file cleanup
symlink refusal without following the target
FIFO/socket refusal
different-device refusal
same-device different-mount-ID refusal
top-level identity mismatch
child identity mismatch
injected scan/unlink/rmdir failure
repeated cleanup after CLEANED returns true
repeated cleanup after FAILED returns false
cleanup after RELEASED returns false and does not delete the published path
```

The integration-level cleanup failure tests in app, profile sync, and
repositories must continue to assert redacted errors and retained uncertain
artifacts, not malicious same-UID safety.

- [ ] **Step 2: Run focused cleanup tests and verify RED**

Run:

```bash
cd docker/hermes-agent/bootstrap
PYTHONPATH=. python3 -m unittest \
  tests.test_filesystem \
  tests.test_app \
  tests.test_profile_sync \
  tests.test_repositories -v
```

Expected: new terminal-state and mount-ID tests FAIL against the current
quarantine implementation.

- [ ] **Step 3: Add mount-ID and cleanup-state helpers**

Use explicit state:

```python
class _PrivateDirectoryState(Enum):
    ACTIVE = "active"
    CLEANED = "cleaned"
    RELEASED = "released"
    FAILED = "failed"
```

On Linux, parse `mnt_id:` from `/proc/self/fdinfo/<fd>` for the captured root and
each opened directory or regular file. Missing, malformed, or inconsistent
mount information fails cleanup closed. Device mismatch also fails closed.

- [ ] **Step 4: Implement two-pass no-follow cleanup**

Remove `ctypes`, `_load_renameat2`, `_transfer_twice`,
`_quarantine_entry`, `_rename_noreplace_at`, `_unused_cleanup_name`, and their
constants.

Under the already held engine lock:

1. Preflight the complete captured tree by descriptor. Accept only directories
   and single-link regular files created within the captured mount and device.
   Reject symlinks and special files.
2. Rewalk by descriptor and remove files and child directories with
   descriptor-relative `unlink` and `rmdir`.
3. Revalidate the captured top-level identity and remove its registered name
   from the retained parent descriptor.
4. Set `CLEANED` only after the top-level removal succeeds.
5. On any exception, set `FAILED`, close descriptors, and return `False`.

`release()` is valid only from `ACTIVE`, closes descriptors, and sets
`RELEASED`. `cleanup()` returns `True` only for a completed `CLEANED` state;
`FAILED` and `RELEASED` return `False`.

- [ ] **Step 5: Run focused cleanup tests**

Run:

```bash
cd docker/hermes-agent/bootstrap
PYTHONPATH=. python3 -m unittest \
  tests.test_filesystem \
  tests.test_app \
  tests.test_profile_sync \
  tests.test_repositories -v
```

Expected: PASS with no `renameat2`-dependent test.

- [ ] **Step 6: Commit Task 3**

Run:

```bash
git add \
  docker/hermes-agent/bootstrap/hermes_bootstrap/filesystem.py \
  docker/hermes-agent/bootstrap/tests/test_filesystem.py \
  docker/hermes-agent/bootstrap/tests/test_app.py \
  docker/hermes-agent/bootstrap/tests/test_profile_sync.py \
  docker/hermes-agent/bootstrap/tests/test_repositories.py
git commit -m "refactor: bound Hermes private cleanup guarantees"
```

---

### Task 4: Align Documentation And Provenance Gates

**Files:**
- Modify:
  `docs/hermes-agent/bootstrap.md`
- Modify:
  `docs/hermes-agent/bootstrap-design.md`
- Modify:
  `docs/hermes-agent/profile-local-authoritative-sync-design.md`
- Modify:
  `docs/hermes-agent/plans/2026-07-23-hermes-profile-local-sync.md`
- Update execution evidence (git-ignored):
  `.superpowers/sdd/final-whole-branch-fix-report.md`
- Modify:
  `docker/hermes-agent/bootstrap/tests/test_hermes_home_wrapper_contract.py`

**Interfaces:**
- Consumes Task 1's canonical lock path and Task 2's
  `local_profile_changed` semantics.
- Extends the existing hermes-home wrapper provenance gate with exact tree-mode
  checks and a second pre-publication invocation.

- [ ] **Step 1: Add failing provenance mode tests**

In `test_hermes_home_wrapper_contract.py`, inspect committed tree entries with:

```bash
git ls-tree <commit> -- scripts/profile_sync.sh
git ls-tree HEAD -- <fixture-path>
```

Require both modes to equal `100755` in addition to the existing byte, blob-ID,
and SHA-256 checks. Add a fixture-mode failure case that fails without relying
on worktree executable-bit behavior.

- [ ] **Step 2: Run the provenance contract and verify RED**

Run:

```bash
cd docker/hermes-agent/bootstrap
PYTHONPATH=. python3 -m unittest \
  tests.test_hermes_home_wrapper_contract -v
```

Expected: FAIL because committed tree modes are not yet asserted.

- [ ] **Step 3: Implement and document the two provenance gates**

Make the test report a redacted contract failure for either non-`100755` mode.
In the publication plan, require the same gate:

```text
before the dotfiles PR is published
immediately before the hermes-home PR is published after dotfiles merges
```

The second run is mandatory even if the first run passed.

- [ ] **Step 4: Correct the architecture and operations documentation**

Document the canonical engine lock, supported threat model, late snapshot
comparison, `local_profile_changed`, and existing-profile no-overwrite rule.
Replace all claims that there is no global operation lock or that cleanup
defeats malicious same-UID replacement.

Clarify:

```text
a declared empty owned root is invalid
a nested empty directory under a nonempty owned root is omitted from Git
profile-local-sync exists on the ordered hermes-home dependency branch and
becomes active only after that branch merges and the root distribution is
applied
```

Update the final fix report to remove the unsupported “never deletes the
replacement tree” claim and record the accepted threat model and new test
evidence.

- [ ] **Step 5: Run documentation and provenance checks**

Run:

```bash
git diff --check
pre-commit run --files \
  docs/hermes-agent/bootstrap.md \
  docs/hermes-agent/bootstrap-design.md \
  docs/hermes-agent/profile-local-authoritative-sync-design.md \
  docs/hermes-agent/plans/2026-07-23-hermes-profile-local-sync.md \
  docker/hermes-agent/bootstrap/tests/test_hermes_home_wrapper_contract.py
```

Expected: PASS.

- [ ] **Step 6: Commit Task 4**

Run:

```bash
git add \
  docs/hermes-agent/bootstrap.md \
  docs/hermes-agent/bootstrap-design.md \
  docs/hermes-agent/profile-local-authoritative-sync-design.md \
  docs/hermes-agent/plans/2026-07-23-hermes-profile-local-sync.md \
  docker/hermes-agent/bootstrap/tests/test_hermes_home_wrapper_contract.py
git commit -m "docs: align Hermes profile sync safety contract"
```

---

## Final Verification And Handoff

After all four task reviews are clean:

```bash
task hermes:bootstrap:test
pre-commit run --all-files
git status --short --branch
```

Expected:

```text
all bootstrap tests pass
all pre-commit hooks pass
only codex/hermes-profile-local-sync is checked out
the worktree is clean
```

Then resume Task 8 in
`docs/hermes-agent/plans/2026-07-23-hermes-profile-local-sync.md`: publish and
merge dotfiles first, rerun the complete wrapper provenance gate, publish and
merge `hermes-home`, and finally execute the Task 9 cron and Slack acceptance
checks.
