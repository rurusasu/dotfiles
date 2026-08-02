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
