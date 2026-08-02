# Task 1 report: failing Gmail MCP contract tests

## Status

Task 1 is complete. The contract tests were written first, run in the RED
state, and committed without implementing production behavior.

Commit: `4fd85175` (`test: add Hermes Gmail MCP contract tests`)

## Changed files

- `tests/bash/hermes_gmail_mcp.bats`
  - Requires the official Gmail MCP URL.
  - Requires `auth: oauth`, both Gmail scopes, and the six read/draft tools.
  - Rejects send, delete, and label-mutation tool names.
- `docker/hermes-agent/bootstrap/tests/test_google_gmail.py`
  - Defines the expected Gmail MCP configuration.
  - Covers installation for root and named-profile targets while preserving
    unrelated servers.
  - Covers validation of missing, altered, scope-incomplete, and forbidden-tool
    configurations.
- `docker/hermes-agent/bootstrap/tests/test_envfiles.py`
  - Requires `GMAIL_MCP_CLIENT_ID` and `GMAIL_MCP_CLIENT_SECRET`.
  - Requires values derived from the Calendar OAuth JSON to be present in the
    private, immutable profile environment and redacted from its `repr`.
- `docker/hermes-agent/bootstrap/tests/test_google_calendar.py`
  - Ensures Calendar installation preserves an existing Gmail server entry.

## TDD RED evidence

### Bats

Command:

```text
bats tests/bash/hermes_gmail_mcp.bats
```

Result: failed, 0/2 tests passed. The source module
`docker/hermes-agent/bootstrap/hermes_bootstrap/google_gmail.py` does not exist,
so the Gmail declarations are absent.

### Focused unittest

The requested host command could not import the repository test dependencies:
the host `python3` has neither `yaml` nor `dotenv`. The same focused command was
therefore run inside the existing Hermes bootstrap runtime image, which has the
project dependencies:

```text
docker run --rm -v "$PWD:/workspace" -w /workspace \
  local/hermes-bootstrap-runtime-current \
  /opt/hermes/.venv/bin/python -m unittest \
  docker.hermes-agent.bootstrap.tests.test_google_gmail \
  docker.hermes-agent.bootstrap.tests.test_envfiles -v
```

Result: failed during test-module import, 0 tests run, for the expected missing
behavior reasons:

- `ModuleNotFoundError: No module named 'hermes_bootstrap.google_gmail'`
- `ImportError: cannot import name 'GMAIL_MCP_KEYS' from hermes_bootstrap.envfiles`

No production code was added or modified.

## Validation

- `git diff --check`: passed.
- No secrets or real OAuth credentials were added.
- The other pre-commit hooks passed. The `hermes-bootstrap-tests` hook was
  intentionally skipped for the commit because its full container gate must
  remain RED until Task 2 implements Gmail behavior.

## Concerns

- The Python tests cannot reach their individual assertions until Task 2 adds
  the Gmail bootstrap module and environment key set; this is intentional for
  the required RED phase.
- The direct host focused command remains blocked by missing host Python
  dependencies; the dependency-complete runtime execution provides the
  authoritative RED result.

## Fix round 1

### Review findings addressed

- `test_validation_rejects_a_missing_or_altered_gmail_entry` now has separate
  `missing` and `altered` subcases. The altered case changes the Gmail MCP URL
  to a non-contract path and asserts `ValidationError`.
- The OAuth environment assertions now verify the existing implementation
  contract directly: both values are present under the expected keys, each is
  an `_SecretEnvironmentValue`, each individual value renders as
  `'[REDACTED]'`, the full mapping representation omits both plaintext values,
  and the `MappingProxyType` remains immutable.
- The grep brittleness observation remains a minor ledger item; no unrelated
  source-path or production change was needed for this fix.

### Changed files

- `docker/hermes-agent/bootstrap/tests/test_google_gmail.py`
- `docker/hermes-agent/bootstrap/tests/test_envfiles.py`
- `.superpowers/sdd/2026-08-02-hermes-gmail-mcp/task-1-report.md`

### Verification commands and results

```text
git diff --check
```

Passed.

```text
bats tests/bash/hermes_gmail_mcp.bats
```

Failed as expected: 2/2 tests remain RED because the Gmail source module is
not implemented yet.

```text
docker run --rm -v "$PWD:/workspace" -w /workspace \
  local/hermes-bootstrap-runtime-current \
  /opt/hermes/.venv/bin/python -m unittest \
  docker.hermes-agent.bootstrap.tests.test_google_gmail \
  docker.hermes-agent.bootstrap.tests.test_envfiles -v
```

Failed as expected during import, with 2 errors and 0 tests run:

- `ModuleNotFoundError: No module named 'hermes_bootstrap.google_gmail'`
- `ImportError: cannot import name 'GMAIL_MCP_KEYS' from hermes_bootstrap.envfiles`

The dependency-complete runtime was used because the host Python environment
lacks `yaml` and `dotenv`. No production code was added or modified.
