# Amendment Task 2 Report

## Result

Implemented full late local-profile snapshot revalidation immediately before
`Transaction.begin` and the final existing-profile no-overwrite policy.

Implementation commit: `5b00817`

## RED Evidence

Host command:

```bash
cd docker/hermes-agent/bootstrap
PYTHONPATH=. python3 -m unittest tests.test_profile_snapshot -v
```

Result: test collection stopped with 1 error because the host interpreter does
not provide `yaml` (`ModuleNotFoundError: No module named 'yaml'`).

Hermes container snapshot RED:

```bash
docker exec hermes rm -rf /tmp/task-2-bootstrap
docker cp docker/hermes-agent/bootstrap hermes:/tmp/task-2-bootstrap
docker exec -w /tmp/task-2-bootstrap -e PYTHONPATH=. hermes \
  python3 -m unittest tests.test_profile_snapshot -v
```

Result: 61 tests ran; 11 errors. All new errors were the expected absent
`revalidate_profile_snapshots` interface or its absent comparison-scratch
dependency.

Hermes container apply-order/no-overwrite RED:

```bash
docker exec hermes rm -rf /tmp/task-2-agent
docker cp docker/hermes-agent hermes:/tmp/task-2-agent
docker exec -w /tmp/task-2-agent/bootstrap -e PYTHONPATH=. hermes \
  python3 -m unittest \
    tests.test_profile_snapshot \
    tests.test_distributions \
    tests.test_app \
    tests.integration.test_profile_sync_flow -v
```

Result: 179 tests ran; 13 failures and 7 errors. The new failures showed that
late drift still reached the transaction/apply path and that
`replace_existing` was not yet accepted. The run also exposed existing
integration fixture expectations for Task 1's persistent engine lock, which
were updated without changing Task 1 production behavior.

## GREEN Evidence

Final focused and integration command in the Hermes container:

```bash
docker exec hermes rm -rf /tmp/task-2-agent
docker cp docker/hermes-agent hermes:/tmp/task-2-agent
docker exec -w /tmp/task-2-agent/bootstrap -e PYTHONPATH=. hermes \
  python3 -m unittest \
    tests.test_profile_snapshot \
    tests.test_distributions \
    tests.test_app \
    tests.integration.test_profile_sync_flow -v
```

Result: 181 tests ran; 181 passed; 0 failures; 0 errors.

Additional checks:

```bash
docker exec -w /tmp/task-2-agent/bootstrap -e PYTHONPATH=. hermes \
  python3 -m compileall -q \
    hermes_bootstrap \
    tests/test_profile_snapshot.py \
    tests/test_distributions.py \
    tests/test_app.py \
    tests/integration/test_profile_sync_flow.py
git diff --check
```

Result: both commands exited 0 with no output.

## Changed Files

- `docker/hermes-agent/bootstrap/hermes_bootstrap/profile_snapshot.py`
- `docker/hermes-agent/bootstrap/hermes_bootstrap/app.py`
- `docker/hermes-agent/bootstrap/hermes_bootstrap/distributions.py`
- `docker/hermes-agent/bootstrap/tests/test_profile_snapshot.py`
- `docker/hermes-agent/bootstrap/tests/test_app.py`
- `docker/hermes-agent/bootstrap/tests/test_distributions.py`
- `docker/hermes-agent/bootstrap/tests/integration/test_profile_sync_flow.py`
- `.superpowers/sdd/task-2-report.md`

## Self-Review

- Revalidation rebuilds all profile projections with `allow_missing=True` in a
  private child scratch and compares only path-independent immutable fields.
- Canonical manifest edits, same-size/restored-mtime edits, mode changes,
  additions, deletions, renames, directory replacement, missing-target
  creation, and existing-target deletion all map to `local_profile_changed`.
- Comparison scratch is always cleaned. Cleanup failure overrides unchanged
  and drift outcomes with `cleanup_failed`.
- Multi-profile comparison reports the first manifest-order mismatch.
- Revalidation remains after shared remote synchronization and directly before
  `Transaction.begin`.
- Every tested pre-transaction checkpoint rejects both an existing edit and a
  previously missing target creation without transaction start or local apply.
- `replace_existing=False` returns a no-op for a current target, installs only
  a still-missing target, and rejects differing or malformed existing targets
  before snapshots, stale deletion, environment changes, or Hermes install.
- A target created after revalidation but before profile apply survives
  byte-for-byte when the no-overwrite boundary rejects it.
- The lower-level default remains `replace_existing=True` for compatibility.
- The diff is confined to the user-owned Task 2 paths and preserves Task 1's
  held operation window.

## Concerns

- Host Python cannot run the suite because PyYAML is absent; all authoritative
  test runs used the active `hermes` container interpreter as required.
- Hermes currently emits an existing `DeprecationWarning` from
  `hermes_cli/profile_distribution.py`; it did not affect results and is
  outside Task 2 ownership.

## Critical Fix

### Result

Replaced the cached target-existence decision with a transaction-owned atomic
directory reservation. A no-replace install now reaches Hermes only after
`renameat2(..., RENAME_NOREPLACE)` publishes the reserved target successfully.
Rollback and recovery require both the reserved directory identity and its
private transaction nonce, so a race winner or replacement target is preserved.

Implementation commit: `f7687e7`

### RED Evidence

Focused post-probe, post-bookkeeping, and rollback contract command:

```bash
docker exec -w /tmp/task-2-critical-agent/bootstrap -e PYTHONPATH=. hermes \
  python3 -m unittest \
    tests.test_distributions.DistributionTests.test_profile_no_overwrite_rejects_a_target_created_after_the_missing_probe \
    tests.integration.test_profile_sync_flow.ProfileSyncFlowTests.test_profile_created_after_revalidation_survives_no_overwrite_failure \
    tests.integration.test_profile_sync_flow.ProfileSyncFlowTests.test_profile_created_after_reservation_bookkeeping_survives_app_rollback \
    tests.test_transaction.TransactionTests.test_directory_reservation_rollback_removes_only_the_reserved_identity \
    tests.test_transaction.TransactionTests.test_directory_reservation_recovery_preserves_a_replacement_identity \
    -v
```

Result: 5 tests ran; 1 failure and 3 errors. The post-probe test showed
`install_distribution(..., force=True)` was called once. The other errors
showed that `Transaction.reserve_directory` and `_rename_noreplace` did not yet
exist.

Corrected app-level post-probe RED:

```bash
docker exec -w /tmp/task-2-critical-agent/bootstrap -e PYTHONPATH=. hermes \
  python3 -m unittest \
    tests.integration.test_profile_sync_flow.ProfileSyncFlowTests.test_profile_created_after_revalidation_survives_no_overwrite_failure \
    -v
```

Result: 1 test ran; 1 failure because `ApplyError` was not raised after the
target was created following the initial missing probe.

Reservation-marker ownership RED:

```bash
docker exec -w /tmp/task-2-critical-agent/bootstrap -e PYTHONPATH=. hermes \
  python3 -m unittest \
    tests.test_distributions.DistributionTests.test_profile_rejects_the_transaction_reservation_marker \
    -v
```

Result: 1 test ran; 1 failure because the internal marker was still accepted as
distribution-owned content.

### GREEN Evidence

Focused race and reservation command:

```bash
docker exec -w /tmp/task-2-critical-agent/bootstrap -e PYTHONPATH=. hermes \
  python3 -m unittest \
    tests.test_distributions.DistributionTests.test_profile_no_overwrite_rejects_a_target_created_after_the_missing_probe \
    tests.integration.test_profile_sync_flow.ProfileSyncFlowTests.test_profile_created_after_revalidation_survives_no_overwrite_failure \
    tests.integration.test_profile_sync_flow.ProfileSyncFlowTests.test_profile_created_after_reservation_bookkeeping_survives_app_rollback \
    tests.test_transaction.TransactionTests.test_directory_reservation_rollback_removes_only_the_reserved_identity \
    tests.test_transaction.TransactionTests.test_directory_reservation_recovery_preserves_a_replacement_identity \
    tests.test_transaction.TransactionTests.test_directory_reservation_commit_removes_the_private_marker \
    -v
```

Result: 6 tests ran; 6 passed; 0 failures; 0 errors.

Complete Task 2 command in a fresh Hermes container copy:

```bash
docker exec -w /tmp/task-2-critical-final/bootstrap -e PYTHONPATH=. hermes \
  python3 -m unittest \
    tests.test_profile_snapshot \
    tests.test_distributions \
    tests.test_app \
    tests.integration.test_profile_sync_flow \
    -v
```

Result: 184 tests ran; 184 passed; 0 failures; 0 errors.

Complete transaction command:

```bash
docker exec -w /tmp/task-2-critical-final/bootstrap -e PYTHONPATH=. hermes \
  python3 -m unittest tests.test_transaction -v
```

Result: 48 tests ran; 48 passed; 0 failures; 0 errors.

Additional checks:

```bash
docker exec -w /tmp/task-2-critical-final/bootstrap -e PYTHONPATH=. hermes \
  python3 -m compileall -q \
    hermes_bootstrap \
    tests/test_profile_snapshot.py \
    tests/test_distributions.py \
    tests/test_app.py \
    tests/test_transaction.py \
    tests/integration/test_profile_sync_flow.py
git diff --check
```

Result: both commands exited 0 with no output.

### Changed Files

- `docker/hermes-agent/bootstrap/hermes_bootstrap/distributions.py`
- `docker/hermes-agent/bootstrap/hermes_bootstrap/transaction.py`
- `docker/hermes-agent/bootstrap/tests/test_distributions.py`
- `docker/hermes-agent/bootstrap/tests/test_transaction.py`
- `docker/hermes-agent/bootstrap/tests/integration/test_profile_sync_flow.py`
- `.superpowers/sdd/task-2-report.md`

### Self-Review

- The initial target probe is used only for the current-profile no-op. A
  missing no-replace target must be won by atomic reservation before the forced
  Hermes API can run.
- Reservation bookkeeping is write-ahead: the private directory and nonce are
  journaled before atomic publication. A competing target after the ready
  journal entry causes `RENAME_NOREPLACE` to fail without calling Hermes.
- Rollback and crash recovery remove a target only when its directory identity
  and private nonce both match. This also handles immediate inode reuse after a
  replacement is created.
- A transaction-created `profiles` parent uses empty-only rollback. An external
  child prevents parent removal and survives intact.
- Successful commit and committed crash recovery preserve installed files and
  remove only the matching reservation nonce.
- Version 3 journals add directory reservations while recovery continues to
  accept version 2 snapshot-only journals.
- The internal nonce filename is rejected as profile distribution-owned
  content, preventing the install payload from invalidating rollback ownership.
- Existing replacement behavior remains behind `replace_existing=True`; all
  Task 1 and Task 2 coverage remains green.

### Concerns

- Atomic reservation requires Linux `renameat2` with `RENAME_NOREPLACE`, which
  is available in the authoritative Hermes container. Unsupported runtimes
  fail closed before Hermes install.
- Hermes still emits the pre-existing `profile_distribution.py`
  `DeprecationWarning`; it is outside this fix.

## Post-Publish Critical Fix

### Result

Moved the complete no-replace profile installation into a private
same-filesystem Hermes home. Hermes installation, canonical source stamping,
managed profile environment preparation, and tree synchronization now finish
before the completed directory is adopted by the transaction journal and
published with `RENAME_NOREPLACE`.

Implementation commit: `f786ace`

### RED Evidence

Post-publication replacement and direct v2 recovery command in a fresh Hermes
container copy:

```bash
docker exec hermes rm -rf /tmp/task-2-post-publish-red
docker cp docker/hermes-agent hermes:/tmp/task-2-post-publish-red
docker exec -w /tmp/task-2-post-publish-red/bootstrap -e PYTHONPATH=. hermes \
  python3 -m unittest \
    tests.test_distributions.DistributionTests.test_profile_no_overwrite_never_writes_after_published_target_is_replaced \
    tests.integration.test_profile_sync_flow.ProfileSyncFlowTests.test_post_publish_replacement_survives_env_merge_and_validation \
    tests.test_transaction.TransactionTests.test_version_two_active_journal_recovery_restores_snapshot \
    tests.test_transaction.TransactionTests.test_version_two_committed_journal_recovery_retains_snapshot \
    -v
```

Result: 4 tests ran; 2 passed and 2 failed. The distribution failure showed the
external mode-0600 `config.yaml` replaced by staged content plus Hermes-created
directories after `reserve_directory` returned. The app failure showed that
the external `.env` was merged into a valid managed file, so the expected
validation error was not raised. Both direct v2 recovery tests passed.

Completed-directory publication API RED:

```bash
docker exec hermes rm -rf /tmp/task-2-publish-api-red
docker cp docker/hermes-agent hermes:/tmp/task-2-publish-api-red
docker exec -w /tmp/task-2-publish-api-red/bootstrap -e PYTHONPATH=. hermes \
  python3 -m unittest \
    tests.test_transaction.TransactionTests.test_completed_directory_is_journaled_before_atomic_publication \
    -v
```

Result: 1 test ran; 1 error because `Transaction.publish_directory` did not
exist.

### GREEN Evidence

Focused race, publication, and compatibility command in the final fresh Hermes
container copy:

```bash
docker exec hermes rm -rf /tmp/task-2-post-publish-final
docker cp docker/hermes-agent hermes:/tmp/task-2-post-publish-final
docker exec -w /tmp/task-2-post-publish-final/bootstrap -e PYTHONPATH=. hermes \
  python3 -m unittest \
    tests.test_distributions.DistributionTests.test_profile_no_overwrite_never_writes_after_published_target_is_replaced \
    tests.integration.test_profile_sync_flow.ProfileSyncFlowTests.test_post_publish_replacement_survives_env_merge_and_validation \
    tests.test_transaction.TransactionTests.test_completed_directory_is_journaled_before_atomic_publication \
    tests.test_transaction.TransactionTests.test_version_two_active_journal_recovery_restores_snapshot \
    tests.test_transaction.TransactionTests.test_version_two_committed_journal_recovery_retains_snapshot \
    -v
```

Result: 5 tests ran; 5 passed; 0 failures; 0 errors.

Complete Task 2 command in the same fresh copy:

```bash
docker exec -w /tmp/task-2-post-publish-final/bootstrap -e PYTHONPATH=. hermes \
  python3 -m unittest \
    tests.test_profile_snapshot \
    tests.test_distributions \
    tests.test_app \
    tests.integration.test_profile_sync_flow \
    -v
```

Result: 186 tests ran; 186 passed; 0 failures; 0 errors.

Complete transaction command:

```bash
docker exec -w /tmp/task-2-post-publish-final/bootstrap -e PYTHONPATH=. hermes \
  python3 -m unittest tests.test_transaction -v
```

Result: 51 tests ran; 51 passed; 0 failures; 0 errors.

Additional checks:

```bash
docker exec -w /tmp/task-2-post-publish-final/bootstrap -e PYTHONPATH=. hermes \
  python3 -m compileall -q \
    hermes_bootstrap \
    tests/test_profile_snapshot.py \
    tests/test_distributions.py \
    tests/test_app.py \
    tests/test_transaction.py \
    tests/integration/test_profile_sync_flow.py
git diff --check
```

Result: both commands exited 0 with no output.

### Changed Files

- `docker/hermes-agent/bootstrap/hermes_bootstrap/app.py`
- `docker/hermes-agent/bootstrap/hermes_bootstrap/distributions.py`
- `docker/hermes-agent/bootstrap/hermes_bootstrap/transaction.py`
- `docker/hermes-agent/bootstrap/tests/test_app.py`
- `docker/hermes-agent/bootstrap/tests/test_distributions.py`
- `docker/hermes-agent/bootstrap/tests/test_transaction.py`
- `docker/hermes-agent/bootstrap/tests/integration/test_profile_sync_flow.py`
- `.superpowers/sdd/task-2-report.md` in the separate report commit

### Self-Review

- The Task 2 no-replace path points the official Hermes
  `install_distribution(..., force=True)` API at a descriptor-owned private
  home created directly beneath the data root. The focused test confirms the
  staging home and data root use the same filesystem.
- Hermes installation, installed-manifest source stamping, managed `.env`
  preparation, and staged-tree fsync all complete before transaction
  publication. The focused test confirms every manifest write targets private
  staging rather than the canonical profile.
- `Transaction.publish_directory` first adopts the completed directory as the
  existing v3 `reservation-NNNNNN` journal object, writes its private nonce,
  makes the ready record durable, and only then publishes with
  `RENAME_NOREPLACE`.
- A missing `profiles` parent is reserved nonrecursively only after private
  preparation finishes. The completed target is then the sole publication
  beneath it. A race winner prevents target publication, and parent rollback
  removes only the marker/empty directory while preserving any external child.
- After successful target publication, distributions performs only private
  staging cleanup and result construction. App skips the later canonical
  `.env` merge for every profile that was missing at revalidation, and
  installed-layout validation remains read-only.
- The focused post-publish replacement test copies out the published profile,
  replaces canonical `config.yaml` and `.env`, then exercises app validation
  and rollback. Exact external bytes and modes survive.
- Rollback, active recovery, commit, and committed recovery continue to remove
  or unmark only a canonical directory whose identity and nonce both match the
  ready journal entry. Replacement identities are retained.
- Journal schema version remains 3 with the existing directory-reservation
  record shape. Direct representative version-2 active and committed
  snapshot-journal recovery tests both pass.
- Legacy `replace_existing=True` behavior remains on the prior snapshot-backed
  path. No Task 3 cleanup changes were added.

### Concerns

- Atomic publication still requires Linux `renameat2` with
  `RENAME_NOREPLACE`; unsupported runtimes fail closed before canonical
  publication.
- Hermes still emits the pre-existing `profile_distribution.py`
  `DeprecationWarning`; it did not affect any result and remains outside Task 2.
