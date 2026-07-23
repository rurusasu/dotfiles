# Task 6 Review Fix Report

## Scope

- Branch: `codex/hermes-profile-local-sync`
- Review-fix base commit:
  `f95d0de2adf11b2b73bc03143a60b6c73f8f67aa`
- Original Task 5 base used for still-valid documentation comparison:
  `69fe5fbfd96fdca8c258bf9f0802bb7ccb5506c0`
- Tracked ownership:
  - `docs/hermes-agent/bootstrap-design.md`
  - `docs/hermes-agent/bootstrap.md`
  - `docs/hermes-agent/profile-home-layout.md`
  - `docs/hermes-agent/profile-local-authoritative-sync-design.md`

No code, tests, manifests, plans, or other documentation are owned by this
follow-up.

## Sources Rechecked

- `docker/hermes-agent/bootstrap/hermes_bootstrap/app.py`
- `docker/hermes-agent/bootstrap/hermes_bootstrap/cli.py`
- `docker/hermes-agent/bootstrap/hermes_bootstrap/errors.py`
- `docker/hermes-agent/bootstrap/hermes_bootstrap/profile_snapshot.py`
- `docker/hermes-agent/bootstrap/hermes_bootstrap/profile_sync.py`
- `docker/hermes-agent/bootstrap/hermes_bootstrap/repositories.py`
- `docker/hermes-agent/bootstrap/hermes_bootstrap/transaction.py`
- `docker/hermes-agent/bootstrap/tests/test_app.py`
- `docker/hermes-agent/bootstrap/tests/test_cli.py`
- `docker/hermes-agent/bootstrap/tests/test_profile_sync.py`
- `docker/hermes-agent/bootstrap/tests/integration/test_bootstrap_flow.py`
- `docker/hermes-agent/bootstrap/tests/integration/test_profile_sync_flow.py`
- the four pre-Task-6 documents at commit `69fe5fb`

## Review Fixes

- Restored still-valid bootstrap prerequisites, entrypoints, secret data flow,
  runtime `gh` diagnostics, transaction recovery and rollback, repository
  locks, lifelog migration conflicts, complete typed exit codes, and source
  validation policy.
- Corrected apply ordering to profile preflight/publication, root stage,
  manifest-order profile stages, shared remote synchronization,
  `Transaction.begin`, and transactional apply.
- Made the result example reachable by giving every `changed` profile a
  non-empty diff.
- Removed the generic temporary-file exclusion. The docs now describe the
  actual reserved-path, credential-name, file-type, portability, race, and
  content checks while allowing other regular files under owned paths.
- Corrected failed `apply` diagnostics: the Python exception report is internal;
  the CLI exposes only a safe failed-name message on stderr. Operators obtain
  redacted categories from standalone `sync-profiles`.
- Documented dry-run commit identity, missing-target standalone failure,
  pre-snapshot empty digests, and the stderr-only exit `2`, `6`, and `8`
  boundaries.
- Removed current Nancy checkout observations from general policy. Nancy
  remains covered through manifest-generic ownership and Task 5 fixtures.
- Kept the two-hour cron and Slack delivery as future `hermes-home` Task 7
  work, not deployed behavior.

## Verification

- `pre-commit run --files docs/hermes-agent/bootstrap-design.md
docs/hermes-agent/bootstrap.md docs/hermes-agent/profile-home-layout.md
docs/hermes-agent/profile-local-authoritative-sync-design.md`
  - First run: `treefmt` formatted the exit-code table in `bootstrap.md` and
    returned nonzero because `--fail-on-change` is enabled.
  - Second run: passed. Non-Markdown hooks reported no applicable files.
- `task hermes:bootstrap:test`
  - Passed with exit `0`.
  - The pinned `hermes-bootstrap-test` image target completed and
    `docker/hermes-agent/bootstrap/tests/test_gh_wrapper.sh` printed
    `test_gh_wrapper: PASS`.
- `git diff --check`
  - Passed with no output.
- `git status --short`
  - Listed exactly the four owned tracked documentation files.

## Commit

- `ab2b7a52db88bfe40b8e27ecb7fc0804976b132d`
  (`docs: correct Hermes profile sync operations`)
- The commit contains only the four owned documentation files.

## Concerns

No code or test changes were needed. The Docker build reused its unchanged
cached unit/integration test layer; the required full gate command still
completed successfully, and the live `gh` wrapper check ran and passed.
Post-commit `git diff --check HEAD^ HEAD` passed and the tracked worktree is
clean.

---

## Second Review Fixes

Second-review base:
`ab2b7a52db88bfe40b8e27ecb7fc0804976b132d`.

- Split failed `apply` diagnostics at the real implementation boundary:
  snapshot preparation fails before `profile_report` exists and exposes only
  `profile snapshot rejected (<category>)`; only a nonzero post-preflight
  publication report exposes safe failed names and remains attached to the
  Python exception internally. Both public `apply` failures have empty stdout.
- Qualified validation-before-write wording for
  `Transaction.recover_if_needed`, which runs before secret/credential
  validation and may restore or remove previously journaled managed paths.
- Replaced the named-profile repository-local validator claim. Exact mirrors
  delete workflows, pre-commit, validators, tests, and README files; runtime
  aggregate preflight and dotfiles engine pre-commit/GitHub Actions/integration
  coverage are their replacement gate.
- Scoped the historical `fast`/`full` exit mapping, `ENV_BLOCKED`, and
  two-round repair contract to root or other source repositories that actually
  retain those validation files. Nancy was not added to that historical
  three-profile repository list.
- Restored current lifelog operation:
  `hermes-bootstrap sync-repository lifelog`, `sync_owner: default`, safe
  runtime-token precedence, the lifelog repository lock, and normal read-write
  commit/rebase/push behavior.
- Restored the Windows handler constraint verified in source and Pester tests:
  Phase `2`, order `56`, `RequiresAdmin = false`, preserving user-context
  1Password desktop integration.

## Second Review Verification

- `pre-commit run --files docs/hermes-agent/bootstrap-design.md
docs/hermes-agent/bootstrap.md docs/hermes-agent/profile-home-layout.md
docs/hermes-agent/profile-local-authoritative-sync-design.md`
  - Passed on the first run; `treefmt` made no changes.
- `task hermes:bootstrap:test`
  - Passed with exit `0`.
  - The pinned Docker test target completed and
    `docker/hermes-agent/bootstrap/tests/test_gh_wrapper.sh` printed
    `test_gh_wrapper: PASS`.
- `git diff --check`
  - Passed with no output.
- `git status --short`
  - Listed exactly the four owned tracked documentation files.

## Second Review Commit

- `ccef0a70e40e371899bf85ce73b9845cff72d28d`
  (`docs: refine Hermes sync operations`)
- The commit contains only the four owned documentation files.

## Second Review Concerns

No code or test changes were needed. The Docker build reused its unchanged
cached unit/integration test layer; the required full gate command completed
successfully, and the live `gh` wrapper check ran and passed. Post-commit
`git diff --check HEAD^ HEAD` passed and the tracked worktree is clean.

---

## Combined Final Review Fixes

Combined-final-review base:
`3207830069cb80cf7c66e024190226b86da7cb87`.

### Files

- `docs/hermes-agent/bootstrap.md`
- `docs/hermes-agent/profile-local-authoritative-sync-design.md`
- `docker/hermes-agent/bootstrap/tests/integration/test_profile_sync_flow.py`
- `.superpowers/sdd/hermes-profile-local-sync-task-6-report.md`

### Fixes

- Documented the staged `validate_chrome_mcp_sources` gate after root/profile
  staging and before shared-repository synchronization and
  `Transaction.begin`, including the non-rollback semantics for already
  published named-profile commits.
- Expanded exit `8` to cover staged Chrome source-contract validation and route
  an existing local-authoritative profile to local declarative-config repair
  followed by the documented sync/apply flow.
- Added `/opt/data/shared/.hermes-repository-*` to the guarded cleanup
  inventory, mount-aware quarantine checks, and final clean criteria, matching
  `repositories.py` first-clone staging and `app.py` apply cleanup.
- Added end-to-end coverage for an existing local-authoritative profile whose
  published `config.yaml` violates the Chrome MCP contract. The test checks the
  attached publication report and persisted remote commit, the pre-shared-sync
  and pre-transaction failure boundary, unchanged local target bytes, and zero
  temporary resources.

### Verification

Initial exact regression target:

```sh
docker run --rm -v "$PWD/docker/hermes-agent:/workspace/docker/hermes-agent:ro" -w /workspace/docker/hermes-agent/bootstrap/tests -e PYTHONPATH=/usr/local/lib/hermes-bootstrap local/hermes-bootstrap-runtime /opt/hermes/.venv/bin/python -m unittest integration.test_profile_sync_flow.ProfileSyncFlowTests.test_existing_profile_chrome_validation_fails_after_publication_before_local_mutation
```

- Passed: `Ran 1 test in 0.570s`, `OK`.

Final exact focused targets:

```sh
docker run --rm --entrypoint /opt/hermes/.venv/bin/python -v "$PWD/docker/hermes-agent:/workspace/docker/hermes-agent:ro" -w /workspace/docker/hermes-agent/bootstrap/tests -e PYTHONPATH=/usr/local/lib/hermes-bootstrap local/hermes-bootstrap-runtime -m unittest integration.test_profile_sync_flow.ProfileSyncFlowTests.test_existing_profile_chrome_validation_fails_after_publication_before_local_mutation integration.test_bootstrap_flow.BootstrapFlowTests.test_future_profile_chrome_validation_precedes_remote_and_transaction_mutation test_app.AppTests.test_source_contract_failure_precedes_remote_sync_and_transaction test_app.AppTests.test_apply_cleans_earlier_private_remote_stage_when_later_sync_fails test_repositories.RepositoryTests.test_initial_clone_is_staged_then_moved_without_a_legacy_path
```

- Passed: `Ran 5 tests in 1.019s`, `OK`.

Exact scoped pre-commit command:

```sh
SKIP=hermes-bootstrap-tests pre-commit run --files docs/hermes-agent/bootstrap.md docs/hermes-agent/profile-local-authoritative-sync-design.md docker/hermes-agent/bootstrap/tests/integration/test_profile_sync_flow.py
```

- First run: `treefmt` formatted `docs/hermes-agent/bootstrap.md` and returned
  nonzero because `--fail-on-change` is enabled.
- Second identical run: passed. Non-applicable hooks skipped, including the
  intentionally excluded full Hermes bootstrap suite.
- Third identical post-amend run: `treefmt` formatted the newly tracked report
  and returned nonzero because `--fail-on-change` is enabled.
- Fourth identical post-format run: passed.

```sh
git diff --check
```

- Passed with no output before the fix-tree commit.

### Commit

- Verified fix-only precursor:
  `61e290cf1659b148535bd69244e67d59e17fa3e6`
  (`test: cover profile Chrome validation ordering`).
- This report is amended into that commit. The final content-derived SHA cannot
  be embedded in the commit itself and is returned to the coordinator.

### Concerns

No implementation code changed. The full 447-test suite was intentionally not
rerun; the five exact covering targets passed, and the full-suite pre-commit
hook was explicitly skipped.
