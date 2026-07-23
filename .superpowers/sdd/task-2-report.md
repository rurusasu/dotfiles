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
