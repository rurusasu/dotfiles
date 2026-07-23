# Hermes Chrome MCP Final Fix Report

## Status

DONE

All final-review findings were addressed in the six assigned worktrees. No
branches were pushed and no pull requests were created.

## Source Validator Hardening

Each of the five source validators now:

- Parses `config.yaml` with a `yaml.SafeLoader` subclass that rejects duplicate
  mapping keys recursively at every mapping level.
- Requires
  `type(config["mcp_servers"]["chrome"]["connect_timeout"]) is int`.
- Retains the repository's existing exact `mcp_servers` map equality contract.
- Leaves the source Chrome MCP configuration unchanged.

Each source test suite now runs two negative checks in the pinned Hermes image:

- `connect_timeout: 120.0` must fail the `config-contract` check.
- A duplicate Chrome `url` whose final value is canonical must fail the
  `config-contract` check.

### TDD Evidence

Before the validator changes, both new tests failed independently in every
source repository because each validator returned exit code `0` instead of the
expected validation failure. After the safe loader and exact-type check were
added, all ten targeted regression tests passed.

## Bootstrap Integration Coverage

The bootstrap integration fixture now creates a `future` profile Git
distribution, appends a corresponding `DistributionSource` and Slack
credential declaration to the fixture manifest, and gives the staged source a
floating Chrome timeout.

The test runs through `_patched_runtime`, whose local source adapter calls the
real `stage_distribution`. It does not mock `validate_chrome_mcp_sources`. The
test proves:

- `ValidationError` is raised for the future profile.
- `synchronize_remote` is never called.
- `Transaction.begin` is never called.
- The managed runtime tree remains byte-for-byte unchanged.
- The future profile target is not created.

The production bootstrap ordering already enforced this behavior for every
staged source, so the final-review change in dotfiles is regression coverage
rather than a production-code modification.

## Hoffman Line Endings

Only the three added Chrome lines in `config.yaml` were converted from LF to
CRLF. The mixed-ending file was not normalized.

- Before: `CRLF=172`, lone `LF=20`
- After: `CRLF=175`, lone `LF=17`
- `git diff --ignore-space-at-eol --exit-code -- config.yaml`: pass
- `git -c core.whitespace=cr-at-eol diff --check`: pass
- Working-tree diff for `config.yaml`: 3 additions, 3 deletions

## Verification

### Source Unit Suites

| Repository              | Result          |
| ----------------------- | --------------- |
| hermes-home             | 49 tests passed |
| hermes-profile-rick     | 38 tests passed |
| hermes-profile-hoffman  | 38 tests passed |
| hermes-profile-risarisa | 39 tests passed |
| hermes-profile-nancy    | 38 tests passed |

### Full Source Validators

| Repository              | Result           |
| ----------------------- | ---------------- |
| hermes-home             | pass, 9/9 checks |
| hermes-profile-rick     | pass, 8/8 checks |
| hermes-profile-hoffman  | pass, 8/8 checks |
| hermes-profile-risarisa | pass, 8/8 checks |
| hermes-profile-nancy    | pass, 8/8 checks |

### Dotfiles Bootstrap Suite

`task hermes:bootstrap:test` passed:

- Containerized Python suite: 330 tests passed, 1 existing skip.
- `test_gh_wrapper.sh`: PASS.

The pinned Hermes dependency emitted its existing `re.split(..., maxsplit)`
deprecation warning during the container suite. It did not affect the result.

## Source Commits

| Repository              | Commit    |
| ----------------------- | --------- |
| hermes-home             | `48bfcca` |
| hermes-profile-rick     | `bd39023` |
| hermes-profile-hoffman  | `331241a` |
| hermes-profile-risarisa | `8c2139c` |
| hermes-profile-nancy    | `c397cd6` |

The dotfiles commit SHA is reported in the completion response because this
report is contained in that commit.

## Changed Paths

- `/Users/ktome1995/Program/.worktrees/hermes-home-chrome-mcp/scripts/validate_distribution.py`
- `/Users/ktome1995/Program/.worktrees/hermes-home-chrome-mcp/tests/test_validate_distribution.py`
- `/Users/ktome1995/Program/.worktrees/hermes-profile-rick-chrome-mcp/scripts/validate_distribution.py`
- `/Users/ktome1995/Program/.worktrees/hermes-profile-rick-chrome-mcp/tests/test_validate_distribution.py`
- `/Users/ktome1995/Program/.worktrees/hermes-profile-hoffman-chrome-mcp/config.yaml`
- `/Users/ktome1995/Program/.worktrees/hermes-profile-hoffman-chrome-mcp/scripts/validate_distribution.py`
- `/Users/ktome1995/Program/.worktrees/hermes-profile-hoffman-chrome-mcp/tests/test_validate_distribution.py`
- `/Users/ktome1995/Program/.worktrees/hermes-profile-risarisa-chrome-mcp/scripts/validate_distribution.py`
- `/Users/ktome1995/Program/.worktrees/hermes-profile-risarisa-chrome-mcp/tests/test_validate_distribution.py`
- `/Users/ktome1995/Program/.worktrees/hermes-profile-nancy-chrome-mcp/scripts/validate_distribution.py`
- `/Users/ktome1995/Program/.worktrees/hermes-profile-nancy-chrome-mcp/tests/test_validate_distribution.py`
- `/Users/ktome1995/Program/dotfiles/.worktrees/hermes-chrome-all-profiles/docker/hermes-agent/bootstrap/tests/integration/test_bootstrap_flow.py`
- `/Users/ktome1995/Program/dotfiles/.worktrees/hermes-chrome-all-profiles/.superpowers/sdd/final-fix-report.md`

## Concerns

No rollout-blocking concerns remain. The single bootstrap-suite skip and the
pinned dependency deprecation warning are pre-existing and are recorded above.
