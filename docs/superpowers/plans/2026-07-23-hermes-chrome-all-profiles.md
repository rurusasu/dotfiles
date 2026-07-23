# Hermes Chrome MCP For All Profiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure the Hermes root distribution and every manifest-declared profile distribution configure the canonical `chrome` MCP server, reject source drift before bootstrap mutation, and prove that profile-driven navigation appears in the noVNC Chrome session.

**Architecture:** Each source distribution remains the owner of its complete `config.yaml`; bootstrap never injects or merges MCP configuration. A focused source-contract validator checks every staged distribution before shared-repository synchronization or transaction creation, so current and future manifest profiles fail closed when the canonical Chrome MCP entry is absent or malformed.

**Tech Stack:** Python 3.11, PyYAML, `unittest`, Hermes distribution manifests, Docker Compose, Model Context Protocol over HTTP, Git worktrees, GitHub Actions.

## Global Constraints

- The canonical entry is exactly:

  ```yaml
  mcp_servers:
    chrome:
      url: http://browser-mcp:8080/mcp
      connect_timeout: 120
  ```

- Preserve additional profile MCP servers such as `xapi` and `x-docs`.
- Require `agent.disabled_toolsets` to contain `browser` so the separate built-in browser session cannot be selected.
- Require every distribution manifest to include `config.yaml` in `distribution_owned`.
- Cover the root distribution, every profile in `bootstrap-manifest.yaml`, and profiles added to that manifest later.
- Do not scan or mutate manually created profiles that are absent from the bootstrap manifest.
- Validate all staged `config.yaml` files before `synchronize_remote(...)` and before `Transaction.begin(...)`.
- Reject missing or unowned files, malformed or duplicate-key YAML, non-mapping nodes, an enabled built-in browser, the wrong URL, a missing/wrong/non-integer timeout, and extra keys under `mcp_servers.chrome`.
- Validation errors may identify the distribution name and `config.yaml`, but must not include file contents, staging paths, source URLs, credentials, or parser details.
- Source distributions own complete configuration files; bootstrap must not inject, merge, or repair MCP settings.
- Use branch `codex/chrome-mcp-all-profiles` in every repository with edits and isolate all edits in Git worktrees.
- Do not push branches, create pull requests, merge, or run the production bootstrap until the user explicitly approves publication.

---

## File Map

### `rurusasu/dotfiles`

- Create `docker/hermes-agent/bootstrap/hermes_bootstrap/source_contracts.py`: strict, non-secret validation for staged distribution configuration.
- Create `docker/hermes-agent/bootstrap/tests/test_source_contracts.py`: table-driven source-contract unit tests.
- Modify `docker/hermes-agent/bootstrap/hermes_bootstrap/app.py`: call the validator after all distributions are staged and before remote synchronization.
- Modify `docker/hermes-agent/bootstrap/tests/test_app.py`: preserve orchestration isolation and assert fail-before-mutation ordering.
- Modify `docs/hermes-agent/browser-mcp.md`: document ownership, bootstrap enforcement, and runtime verification.

### `rurusasu/hermes-profile-rick`

- Modify `config.yaml`: add the canonical `chrome` entry without removing `xapi` or `x-docs`.
- Modify `scripts/validate_distribution.py`: require the canonical entry.
- Modify `tests/test_validate_distribution.py`: exercise accepted and rejected Chrome MCP contracts against the pinned Hermes image.

### `rurusasu/hermes-profile-hoffman`

- Modify `config.yaml`: add the canonical `chrome` entry without removing `xapi` or `x-docs`.
- Modify `scripts/validate_distribution.py`: require the canonical entry.
- Modify `tests/test_validate_distribution.py`: exercise accepted and rejected Chrome MCP contracts against the pinned Hermes image.

### `rurusasu/hermes-profile-risarisa`

- Modify `config.yaml`: add the canonical `chrome` entry without removing `xapi` or `x-docs`.
- Modify `scripts/validate_distribution.py`: require the canonical entry.
- Modify `tests/test_validate_distribution.py`: exercise accepted and rejected Chrome MCP contracts against the pinned Hermes image.

### `rurusasu/hermes-profile-nancy`

- Create `distribution.yaml`: make Nancy a valid bootstrap distribution.
- Create `scripts/validate_distribution.py`: provide the same fail-closed distribution validation surface as the established profiles, with Nancy-specific contracts.
- Create `tests/test_validate_distribution.py`: verify manifest, config, payload, policy, secret scanning, parser compatibility, and user-data preservation behavior.
- Create `.github/workflows/distribution.yml`: run full validation for pull requests.
- Create `.pre-commit-config.yaml`: run fast validation on commit and full validation on push.
- Modify `.gitignore`: ignore generated validation reports.
- Modify `config.yaml`: add the canonical `chrome` MCP entry.

## Worktree Layout

The dotfiles worktree already exists:

```text
/Users/ktome1995/Program/dotfiles/.worktrees/hermes-chrome-all-profiles
```

Create source-repository worktrees from current `origin/main` before their tasks:

```bash
git -C /Users/ktome1995/Program/hermes-profile-rick fetch origin main
git -C /Users/ktome1995/Program/hermes-profile-rick worktree add -b codex/chrome-mcp-all-profiles /Users/ktome1995/Program/.worktrees/hermes-profile-rick-chrome-mcp origin/main

git -C /Users/ktome1995/Program/hermes-profile-hoffman fetch origin main
git -C /Users/ktome1995/Program/hermes-profile-hoffman worktree add -b codex/chrome-mcp-all-profiles /Users/ktome1995/Program/.worktrees/hermes-profile-hoffman-chrome-mcp origin/main

git -C /Users/ktome1995/Program/hermes-profile-risarisa fetch origin main
git -C /Users/ktome1995/Program/hermes-profile-risarisa worktree add -b codex/chrome-mcp-all-profiles /Users/ktome1995/Program/.worktrees/hermes-profile-risarisa-chrome-mcp origin/main

gh repo clone rurusasu/hermes-profile-nancy /Users/ktome1995/Program/hermes-profile-nancy
git -C /Users/ktome1995/Program/hermes-profile-nancy fetch origin main
git -C /Users/ktome1995/Program/hermes-profile-nancy worktree add -b codex/chrome-mcp-all-profiles /Users/ktome1995/Program/.worktrees/hermes-profile-nancy-chrome-mcp origin/main
```

Expected after each `worktree add`: `Preparing worktree (new branch 'codex/chrome-mcp-all-profiles')`.

### Task 1: Enforce The Chrome MCP Source Contract In Bootstrap

**Repository:** `rurusasu/dotfiles`

**Files:**

- Create: `docker/hermes-agent/bootstrap/hermes_bootstrap/source_contracts.py`
- Create: `docker/hermes-agent/bootstrap/tests/test_source_contracts.py`
- Modify: `docker/hermes-agent/bootstrap/hermes_bootstrap/app.py:37-40,131-135`
- Modify: `docker/hermes-agent/bootstrap/tests/test_app.py:61-70,167-231`

**Interfaces:**

- Consumes: `StagedSource(declaration: DistributionSource, path: Path, commit: str)` from `hermes_bootstrap.git`.
- Produces: `validate_chrome_mcp_sources(staged: Sequence[StagedSource]) -> None`.
- Raises: `ValidationError` with the distribution name and `config.yaml`, without chained parser/file exceptions.

- [ ] **Step 1: Write table-driven failing source-contract tests**

Create `docker/hermes-agent/bootstrap/tests/test_source_contracts.py` with helpers that build immutable staged sources:

```python
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path


BOOTSTRAP_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BOOTSTRAP_ROOT))

from hermes_bootstrap.errors import ValidationError
from hermes_bootstrap.git import StagedSource
from hermes_bootstrap.models import DistributionSource
from hermes_bootstrap.source_contracts import validate_chrome_mcp_sources


VALID_CONFIG = """\
model:
  provider: openai-codex
mcp_servers:
  chrome:
    url: http://browser-mcp:8080/mcp
    connect_timeout: 120
  retained:
    url: https://example.invalid/mcp
"""


class SourceContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def staged(self, name: str, config: str | None) -> StagedSource:
        path = self.root / name
        path.mkdir()
        if config is not None:
            (path / "config.yaml").write_text(config, encoding="utf-8")
        declaration = DistributionSource(
            name=name,
            source=f"https://github.com/example/{name}.git",
            ref="main",
            target=Path("/opt/data") if name == "default" else Path("/opt/data/profiles") / name,
            manifest_name="root-distribution.yaml" if name == "default" else "distribution.yaml",
        )
        return StagedSource(declaration=declaration, path=path, commit="a" * 40)

    def test_accepts_root_and_profiles_while_preserving_other_servers(self) -> None:
        staged = (
            self.staged("default", VALID_CONFIG),
            self.staged("rick", VALID_CONFIG),
        )

        validate_chrome_mcp_sources(staged)

    def test_rejects_every_noncanonical_shape_without_exposing_values(self) -> None:
        invalid = {
            "missing-file": None,
            "malformed-yaml": "mcp_servers: [\n",
            "duplicate-key": """\
mcp_servers:
  chrome:
    url: http://browser-mcp:8080/mcp
    url: https://secret.invalid/mcp
    connect_timeout: 120
""",
            "top-level-sequence": "- mcp_servers\n",
            "mcp-sequence": "mcp_servers: []\n",
            "missing-chrome": "mcp_servers: {}\n",
            "chrome-sequence": "mcp_servers:\n  chrome: []\n",
            "wrong-url": """\
mcp_servers:
  chrome:
    url: https://secret.invalid/mcp
    connect_timeout: 120
""",
            "missing-timeout": """\
mcp_servers:
  chrome:
    url: http://browser-mcp:8080/mcp
""",
            "string-timeout": """\
mcp_servers:
  chrome:
    url: http://browser-mcp:8080/mcp
    connect_timeout: "120"
""",
            "boolean-timeout": """\
mcp_servers:
  chrome:
    url: http://browser-mcp:8080/mcp
    connect_timeout: true
""",
            "wrong-timeout": """\
mcp_servers:
  chrome:
    url: http://browser-mcp:8080/mcp
    connect_timeout: 60
""",
            "extra-chrome-key": """\
mcp_servers:
  chrome:
    url: http://browser-mcp:8080/mcp
    connect_timeout: 120
    token: secret-marker
""",
        }
        for case, config in invalid.items():
            with self.subTest(case=case):
                staged = self.staged(case, config)
                with self.assertRaises(ValidationError) as caught:
                    validate_chrome_mcp_sources((staged,))
                message = str(caught.exception)
                self.assertIn(case, message)
                self.assertIn("config.yaml", message)
                self.assertNotIn("secret-marker", message)
                self.assertNotIn("secret.invalid", message)
                self.assertIsNone(caught.exception.__cause__)

    def test_manifest_additions_are_covered_without_a_profile_allowlist(self) -> None:
        stages = (
            self.staged("default", VALID_CONFIG),
            self.staged("rick", VALID_CONFIG),
            self.staged("future-profile", "mcp_servers: {}\n"),
        )

        with self.assertRaisesRegex(ValidationError, "future-profile.*config.yaml"):
            validate_chrome_mcp_sources(stages)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the bootstrap suite and verify the new test is red**

Run:

```bash
task hermes:bootstrap:test
```

Expected: non-zero exit while building `hermes-bootstrap-test`, with `ModuleNotFoundError: No module named 'hermes_bootstrap.source_contracts'`.

- [ ] **Step 3: Implement strict staged-source validation**

Create `docker/hermes-agent/bootstrap/hermes_bootstrap/source_contracts.py`:

```python
"""Non-secret contracts for staged Hermes source distributions."""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from typing import NoReturn

import yaml

from .errors import ValidationError
from .git import StagedSource


_CHROME_MCP = {
    "url": "http://browser-mcp:8080/mcp",
    "connect_timeout": 120,
}


class _UniqueKeySafeLoader(yaml.SafeLoader):
    """Safe YAML loader that rejects duplicate keys in every mapping."""

    def construct_mapping(
        self, node: yaml.MappingNode, deep: bool = False
    ) -> dict[object, object]:
        self.flatten_mapping(node)
        mapping: dict[object, object] = {}
        for key_node, value_node in node.value:
            key = self.construct_object(key_node, deep=deep)
            try:
                duplicate = key in mapping
            except TypeError as error:
                raise yaml.constructor.ConstructorError(
                    "while constructing a mapping",
                    node.start_mark,
                    "found unacceptable key",
                    key_node.start_mark,
                ) from error
            if duplicate:
                raise yaml.constructor.ConstructorError(
                    "while constructing a mapping",
                    node.start_mark,
                    "found duplicate key",
                    key_node.start_mark,
                )
            mapping[key] = self.construct_object(value_node, deep=deep)
        return mapping


def validate_chrome_mcp_sources(staged: Sequence[StagedSource]) -> None:
    """Require the canonical Chrome MCP entry in every staged distribution."""

    for source in staged:
        try:
            with (source.path / "config.yaml").open(encoding="utf-8") as handle:
                config = yaml.load(handle, Loader=_UniqueKeySafeLoader)
        except (OSError, UnicodeError, yaml.YAMLError):
            _invalid(source)

        if not isinstance(config, Mapping):
            _invalid(source)
        mcp_servers = config.get("mcp_servers")
        if not isinstance(mcp_servers, Mapping):
            _invalid(source)
        chrome = mcp_servers.get("chrome")
        if not isinstance(chrome, Mapping) or dict(chrome) != _CHROME_MCP:
            _invalid(source)


def _invalid(source: StagedSource) -> NoReturn:
    name = source.declaration.name
    raise ValidationError(
        f"distribution {name!r} config.yaml has invalid Chrome MCP configuration"
    ) from None
```

- [ ] **Step 4: Insert validation before all synchronization and mutation**

In `app.py`, import the new function:

```python
from .source_contracts import validate_chrome_mcp_sources
```

Then change the staged-source section of `_apply_sensitive(...)` to:

```python
        scratch = _private_scratch(manifest.data_root)
        staged = [
            stage_distribution(source, scratch, auth)
            for source in _distributions(manifest)
        ]
        validate_chrome_mcp_sources(staged)
        for repo in manifest.shared_repositories:
            remote_results.append((repo, synchronize_remote(repo, auth)))

        tx = Transaction.begin(manifest.data_root)
```

- [ ] **Step 5: Add orchestration tests for ordering and fail-before-mutation**

In `AppTests.setUp`, install a default no-op patch so existing orchestration tests remain focused:

```python
        from hermes_bootstrap import app

        source_contract_patcher = mock.patch.object(
            app, "validate_chrome_mcp_sources"
        )
        self.validate_chrome_mcp_sources = source_contract_patcher.start()
        self.addCleanup(source_contract_patcher.stop)
```

In `test_apply_recovers_before_reading_secrets_and_network_before_transaction`, set:

```python
        self.validate_chrome_mcp_sources.side_effect = (
            lambda staged: events.append(
                "source-contract:" + ",".join(
                    stage.declaration.name for stage in staged
                )
            )
        )
```

and require this event between `stage:rick` and `sync:lifelog`:

```python
                "stage:default",
                "stage:rick",
                "source-contract:default,rick",
                "sync:lifelog",
```

Add a second test:

```python
    def test_source_contract_failure_precedes_remote_sync_and_transaction(self) -> None:
        from hermes_bootstrap import app

        secrets = mock.Mock(
            github_token="token",
            redactor=SecretRedactor(("token",)),
        )
        staged = mock.Mock()
        self.validate_chrome_mcp_sources.side_effect = ValidationError(
            "distribution 'future-profile' config.yaml has invalid Chrome MCP configuration"
        )

        with (
            mock.patch.object(app, "load_manifest", return_value=self.manifest),
            mock.patch.object(app.Transaction, "recover_if_needed"),
            mock.patch.object(app, "read_secret_payload", return_value=secrets),
            mock.patch.object(app, "_validate_remote_credentials"),
            mock.patch.object(app, "_validate_profile_credentials"),
            mock.patch.object(app, "stage_distribution", return_value=staged),
            mock.patch.object(app, "synchronize_remote") as synchronize,
            mock.patch.object(app.Transaction, "begin") as begin,
        ):
            with self.assertRaisesRegex(
                ValidationError, "future-profile.*config.yaml"
            ):
                app.apply(Path("manifest.yaml"), io.StringIO("payload"))

        self.assertEqual(
            self.validate_chrome_mcp_sources.call_args.args[0],
            [staged, staged],
        )
        synchronize.assert_not_called()
        begin.assert_not_called()
```

- [ ] **Step 6: Run the full bootstrap test suite**

Run:

```bash
task hermes:bootstrap:test
```

Expected: Docker test stage completes with all Python tests passing, followed by `test_gh_wrapper: PASS`.

- [ ] **Step 7: Commit the bootstrap enforcement**

```bash
git add docker/hermes-agent/bootstrap/hermes_bootstrap/source_contracts.py
git add docker/hermes-agent/bootstrap/hermes_bootstrap/app.py
git add docker/hermes-agent/bootstrap/tests/test_source_contracts.py
git add docker/hermes-agent/bootstrap/tests/test_app.py
git commit -m "feat: enforce Chrome MCP in Hermes distributions"
```

### Task 2: Add Chrome MCP To Rick

**Repository:** `rurusasu/hermes-profile-rick`

**Files:**

- Modify: `config.yaml`
- Modify: `scripts/validate_distribution.py`
- Modify: `tests/test_validate_distribution.py`

**Interfaces:**

- Consumes: the repository's `config-contract` validator check.
- Produces: a Rick distribution whose `mcp_servers` retains `xapi` and `x-docs` and adds canonical `chrome`.

- [ ] **Step 1: Make the fixture describe the desired contract and add real-image tests**

In the fixture `config.yaml` string in `tests/test_validate_distribution.py`, make `mcp_servers` begin with:

```yaml
mcp_servers:
  chrome:
    url: http://browser-mcp:8080/mcp
    connect_timeout: 120
  xapi:
```

Add these tests to `DistributionValidatorTests`:

```python
    def test_real_config_contract_accepts_canonical_chrome_mcp(self) -> None:
        self.require_real_docker()

        completed = self.run_validator(
            "fast", "--json", environment=os.environ.copy()
        )

        self.assertEqual(completed.returncode, 0, completed.stdout)

    def test_real_config_contract_rejects_wrong_chrome_endpoint(self) -> None:
        self.require_real_docker()
        config_path = self.fixture.root / "config.yaml"
        config_path.write_text(
            config_path.read_text(encoding="utf-8").replace(
                "http://browser-mcp:8080/mcp",
                "https://wrong.invalid/mcp",
            ),
            encoding="utf-8",
        )

        completed = self.run_validator(
            "fast", "--json", environment=os.environ.copy()
        )

        self.assertEqual(completed.returncode, 1)
        result = self.parse_json(completed)
        contract = next(
            check for check in result["checks"] if check["id"] == "config-contract"
        )
        self.assertEqual(contract["status"], "fail")
```

- [ ] **Step 2: Run the focused test and verify the desired config is rejected**

Run:

```bash
python3 -m unittest tests.test_validate_distribution.DistributionValidatorTests.test_real_config_contract_accepts_canonical_chrome_mcp -v
```

Expected: `FAIL`; the current validator still expects only `xapi` and `x-docs`.

- [ ] **Step 3: Update the validator's complete MCP expectation**

Make `CONFIG_CONTRACT_CODE` assert:

```python
assert config["mcp_servers"] == {
    "chrome": {
        "url": "http://browser-mcp:8080/mcp",
        "connect_timeout": 120,
    },
    "xapi": {
        "command": "/usr/local/bin/hermes-xapi-mcp",
        "connect_timeout": 300,
        "env": {
            "X_API_CLIENT_ID": "${X_API_CLIENT_ID}",
            "X_API_CLIENT_SECRET": "${X_API_CLIENT_SECRET}",
        },
    },
    "x-docs": {
        "url": "https://docs.x.com/mcp",
        "connect_timeout": 60,
    },
}
```

- [ ] **Step 4: Add Chrome to Rick's source configuration**

Make the real `config.yaml` `mcp_servers` section begin with:

```yaml
mcp_servers:
  chrome:
    url: http://browser-mcp:8080/mcp
    connect_timeout: 120
  xapi:
```

Leave the complete existing `xapi` and `x-docs` mappings unchanged.

- [ ] **Step 5: Run Rick's unit and full distribution validation**

Run:

```bash
python3 -m unittest discover -s tests -v
python3 scripts/validate_distribution.py full --json
```

Expected: all unit tests pass; the JSON report has `"status":"pass"` and `"exit_code":0`.

- [ ] **Step 6: Commit Rick's source contract**

```bash
git add config.yaml scripts/validate_distribution.py tests/test_validate_distribution.py
git commit -m "feat: add Chrome MCP to Rick"
```

### Task 3: Add Chrome MCP To Hoffman

**Repository:** `rurusasu/hermes-profile-hoffman`

**Files:**

- Modify: `config.yaml`
- Modify: `scripts/validate_distribution.py`
- Modify: `tests/test_validate_distribution.py`

**Interfaces:**

- Consumes: the repository's `config-contract` validator check.
- Produces: a Hoffman distribution whose `mcp_servers` retains `xapi` and `x-docs` and adds canonical `chrome`.

- [ ] **Step 1: Make Hoffman's fixture and real-image tests require Chrome**

Insert the canonical `chrome` mapping before `xapi` in the fixture `config.yaml`:

```yaml
mcp_servers:
  chrome:
    url: http://browser-mcp:8080/mcp
    connect_timeout: 120
  xapi:
```

Add the following complete test methods:

```python
    def test_real_config_contract_accepts_canonical_chrome_mcp(self) -> None:
        self.require_real_docker()

        completed = self.run_validator(
            "fast", "--json", environment=os.environ.copy()
        )

        self.assertEqual(completed.returncode, 0, completed.stdout)

    def test_real_config_contract_rejects_wrong_chrome_endpoint(self) -> None:
        self.require_real_docker()
        config_path = self.fixture.root / "config.yaml"
        config_path.write_text(
            config_path.read_text(encoding="utf-8").replace(
                "http://browser-mcp:8080/mcp",
                "https://wrong.invalid/mcp",
            ),
            encoding="utf-8",
        )

        completed = self.run_validator(
            "fast", "--json", environment=os.environ.copy()
        )

        self.assertEqual(completed.returncode, 1)
        result = self.parse_json(completed)
        contract = next(
            check for check in result["checks"] if check["id"] == "config-contract"
        )
        self.assertEqual(contract["status"], "fail")
```

- [ ] **Step 2: Confirm the current validator rejects the desired fixture**

Run:

```bash
python3 -m unittest tests.test_validate_distribution.DistributionValidatorTests.test_real_config_contract_accepts_canonical_chrome_mcp -v
```

Expected: `FAIL`; `config-contract` has not yet admitted Chrome.

- [ ] **Step 3: Require Chrome while retaining Hoffman's existing servers**

Replace the validator's `assert config["mcp_servers"] == ...` block with:

```python
assert config["mcp_servers"] == {
    "chrome": {
        "url": "http://browser-mcp:8080/mcp",
        "connect_timeout": 120,
    },
    "xapi": {
        "command": "/usr/local/bin/hermes-xapi-mcp",
        "connect_timeout": 300,
        "env": {
            "X_API_CLIENT_ID": "${X_API_CLIENT_ID}",
            "X_API_CLIENT_SECRET": "${X_API_CLIENT_SECRET}",
        },
    },
    "x-docs": {
        "url": "https://docs.x.com/mcp",
        "connect_timeout": 60,
    },
}
```

- [ ] **Step 4: Add Chrome to Hoffman's real config**

Insert exactly:

```yaml
mcp_servers:
  chrome:
    url: http://browser-mcp:8080/mcp
    connect_timeout: 120
  xapi:
```

Keep the existing `xapi` and `x-docs` mappings byte-for-byte except for indentation required by the insertion.

- [ ] **Step 5: Run Hoffman's complete validation**

Run:

```bash
python3 -m unittest discover -s tests -v
python3 scripts/validate_distribution.py full --json
```

Expected: all unit tests pass; the full report contains `"status":"pass"`.

- [ ] **Step 6: Commit Hoffman's source contract**

```bash
git add config.yaml scripts/validate_distribution.py tests/test_validate_distribution.py
git commit -m "feat: add Chrome MCP to Hoffman"
```

### Task 4: Add Chrome MCP To Risarisa

**Repository:** `rurusasu/hermes-profile-risarisa`

**Files:**

- Modify: `config.yaml`
- Modify: `scripts/validate_distribution.py`
- Modify: `tests/test_validate_distribution.py`

**Interfaces:**

- Consumes: the repository's `config-contract` validator check.
- Produces: a Risarisa distribution whose `mcp_servers` retains `xapi` and `x-docs` and adds canonical `chrome`.

- [ ] **Step 1: Add the desired mapping to the fixture and cover it with real Docker**

Insert:

```yaml
mcp_servers:
  chrome:
    url: http://browser-mcp:8080/mcp
    connect_timeout: 120
  xapi:
```

Add:

```python
    def test_real_config_contract_accepts_canonical_chrome_mcp(self) -> None:
        self.require_real_docker()

        completed = self.run_validator(
            "fast", "--json", environment=os.environ.copy()
        )

        self.assertEqual(completed.returncode, 0, completed.stdout)

    def test_real_config_contract_rejects_wrong_chrome_endpoint(self) -> None:
        self.require_real_docker()
        config_path = self.fixture.root / "config.yaml"
        config_path.write_text(
            config_path.read_text(encoding="utf-8").replace(
                "http://browser-mcp:8080/mcp",
                "https://wrong.invalid/mcp",
            ),
            encoding="utf-8",
        )

        completed = self.run_validator(
            "fast", "--json", environment=os.environ.copy()
        )

        self.assertEqual(completed.returncode, 1)
        result = self.parse_json(completed)
        contract = next(
            check for check in result["checks"] if check["id"] == "config-contract"
        )
        self.assertEqual(contract["status"], "fail")
```

- [ ] **Step 2: Prove the test is red before changing the validator**

Run:

```bash
python3 -m unittest tests.test_validate_distribution.DistributionValidatorTests.test_real_config_contract_accepts_canonical_chrome_mcp -v
```

Expected: `FAIL` from the current `config-contract`.

- [ ] **Step 3: Set Risarisa's exact validator expectation**

Use:

```python
assert config["mcp_servers"] == {
    "chrome": {
        "url": "http://browser-mcp:8080/mcp",
        "connect_timeout": 120,
    },
    "xapi": {
        "command": "/usr/local/bin/hermes-xapi-mcp",
        "connect_timeout": 300,
        "env": {
            "X_API_CLIENT_ID": "${X_API_CLIENT_ID}",
            "X_API_CLIENT_SECRET": "${X_API_CLIENT_SECRET}",
        },
    },
    "x-docs": {
        "url": "https://docs.x.com/mcp",
        "connect_timeout": 60,
    },
}
```

- [ ] **Step 4: Add the canonical entry to Risarisa's real config**

Use:

```yaml
mcp_servers:
  chrome:
    url: http://browser-mcp:8080/mcp
    connect_timeout: 120
  xapi:
```

Retain the existing complete `xapi` and `x-docs` values.

- [ ] **Step 5: Run Risarisa's complete validation**

Run:

```bash
python3 -m unittest discover -s tests -v
python3 scripts/validate_distribution.py full --json
```

Expected: all tests pass and the full report has `"exit_code":0`.

- [ ] **Step 6: Commit Risarisa's source contract**

```bash
git add config.yaml scripts/validate_distribution.py tests/test_validate_distribution.py
git commit -m "feat: add Chrome MCP to Risarisa"
```

### Task 5: Formalize Nancy And Add Chrome MCP

**Repository:** `rurusasu/hermes-profile-nancy`

**Files:**

- Create: `distribution.yaml`
- Create: `scripts/validate_distribution.py`
- Create: `tests/test_validate_distribution.py`
- Create: `.github/workflows/distribution.yml`
- Create: `.pre-commit-config.yaml`
- Modify: `.gitignore`
- Modify: `config.yaml`

**Interfaces:**

- Consumes: Hermes profile distribution schema `>=0.18.2`.
- Produces: a `name: nancy`, `version: 0.1.0` distribution with no profile-specific environment requirements and a complete independent validation workflow.

- [ ] **Step 1: Seed Nancy's validator harness from the already-tested Rick worktree**

Copy the robust validator and test harness after Task 2 has passed:

```bash
mkdir -p scripts tests .github/workflows
cp /Users/ktome1995/Program/.worktrees/hermes-profile-rick-chrome-mcp/scripts/validate_distribution.py scripts/validate_distribution.py
cp /Users/ktome1995/Program/.worktrees/hermes-profile-rick-chrome-mcp/tests/test_validate_distribution.py tests/test_validate_distribution.py
cp /Users/ktome1995/Program/.worktrees/hermes-profile-rick-chrome-mcp/.github/workflows/distribution.yml .github/workflows/distribution.yml
cp /Users/ktome1995/Program/.worktrees/hermes-profile-rick-chrome-mcp/.pre-commit-config.yaml .pre-commit-config.yaml
```

This mechanical seed preserves the tested fail-closed Git enumeration, redaction, parser, preservation, and report behavior. The following steps replace every profile-specific contract before the files are committed.

- [ ] **Step 2: Write Nancy's exact distribution manifest**

Create `distribution.yaml`:

```yaml
name: nancy
version: 0.1.0
description: Research and communications strategist profile
hermes_requires: ">=0.18.2"
author: rurusasu
license: private
distribution_owned:
  - .no-bundled-skills
  - SOUL.md
  - config.yaml
  - profile.yaml
  - slack-manifest.json
  - assets/
```

- [ ] **Step 3: Rewrite the validator's Nancy-specific constants and contracts**

Set:

```python
REPOSITORY_NAME = "hermes-profile-nancy"
PROFILE_NAME = "nancy"
```

Replace `MANIFEST_SCHEMA_CODE` with:

```python
MANIFEST_SCHEMA_CODE = r"""
from pathlib import Path
import yaml

expected = {
    "name": "nancy",
    "version": "0.1.0",
    "description": "Research and communications strategist profile",
    "hermes_requires": ">=0.18.2",
    "author": "rurusasu",
    "license": "private",
    "distribution_owned": [
        ".no-bundled-skills",
        "SOUL.md",
        "config.yaml",
        "profile.yaml",
        "slack-manifest.json",
        "assets/",
    ],
}
actual = yaml.safe_load(Path("/repository/distribution.yaml").read_text(encoding="utf-8"))
assert actual == expected
""".strip()
```

Replace `CONFIG_CONTRACT_CODE` with:

```python
CONFIG_CONTRACT_CODE = r"""
from pathlib import Path
import yaml

config = yaml.safe_load(Path("/repository/config.yaml").read_text(encoding="utf-8"))
assert config["model"] == {
    "provider": "openai-codex",
    "default": "gpt-5.6-luna",
}
assert config["terminal"] == {
    "backend": "local",
    "cwd": ".",
    "timeout": 180,
}
assert config["slack"] == {
    "require_mention": True,
    "strict_mention": False,
    "allow_bots": "mentions",
}
assert config["mcp_servers"] == {
    "chrome": {
        "url": "http://browser-mcp:8080/mcp",
        "connect_timeout": 120,
    },
}
for forbidden in ("github", "dashboard"):
    assert forbidden not in config
""".strip()
```

Replace `HERMES_PARSER_CODE` with:

```python
HERMES_PARSER_CODE = r"""
from pathlib import Path
from hermes_cli.profile_distribution import plan_install

p = plan_install("/distribution", Path("/tmp/stage"))
assert p.manifest.name == "nancy"
assert p.manifest.version == "0.1.0"
assert list(p.manifest.env_requires) == []
""".strip()
```

In `PRESERVATION_SCRIPT`, use:

```sh
profile=/tmp/hermes/profiles/nancy
hermes profile install /distribution --name nancy --force -y >/tmp/install.log
```

Set policy requirements in `check_repository_policy(...)` to:

```python
    requirements = [
        "/opt/data/docs/profile-home-layout.md",
        "Keep Hermes' standard filesystem layout intact",
        "/opt/data/core/lifelog/AGENTS.md",
        "do not use profile memories/",
    ]
```

Use Nancy in all pass/fail messages and use:

```python
parser = argparse.ArgumentParser(description="Validate the Nancy Hermes distribution")
```

- [ ] **Step 4: Rewrite the test fixture and identity assertions before running it**

In `tests/test_validate_distribution.py`:

- Set fixture manifest fields exactly to the `distribution.yaml` from Step 2 and remove Rick's `env_requires`.
- Set fixture `SOUL.md` to include all four Nancy policy strings from Step 3.
- Set fixture `config.yaml` to Nancy's model, terminal, slack, and canonical Chrome MCP contract.
- Replace every repository assertion with `hermes-profile-nancy`.
- Replace every manifest/profile identity with `nancy`.
- Replace every runtime path with `/tmp/hermes/profiles/nancy`.
- Remove `test_manifest_schema_requires_xapi_env_requirements`.
- Add this manifest test:

```python
    def test_manifest_schema_rejects_unexpected_environment_requirements(self) -> None:
        self.require_real_docker()
        manifest_path = self.fixture.root / "distribution.yaml"
        manifest_path.write_text(
            manifest_path.read_text(encoding="utf-8")
            + "env_requires:\n"
            + "  - name: UNEXPECTED_SECRET\n"
            + "    description: must be rejected\n",
            encoding="utf-8",
        )

        completed = self.run_validator(
            "fast", "--json", environment=os.environ.copy()
        )

        self.assertEqual(completed.returncode, 1)
        result = self.parse_json(completed)
        manifest = next(
            check for check in result["checks"] if check["id"] == "manifest-schema"
        )
        self.assertEqual(manifest["status"], "fail")
```

Add the canonical/wrong endpoint tests:

```python
    def test_real_config_contract_accepts_canonical_chrome_mcp(self) -> None:
        self.require_real_docker()

        completed = self.run_validator(
            "fast", "--json", environment=os.environ.copy()
        )

        self.assertEqual(completed.returncode, 0, completed.stdout)

    def test_real_config_contract_rejects_wrong_chrome_endpoint(self) -> None:
        self.require_real_docker()
        config_path = self.fixture.root / "config.yaml"
        config_path.write_text(
            config_path.read_text(encoding="utf-8").replace(
                "http://browser-mcp:8080/mcp",
                "https://wrong.invalid/mcp",
            ),
            encoding="utf-8",
        )

        completed = self.run_validator(
            "fast", "--json", environment=os.environ.copy()
        )

        self.assertEqual(completed.returncode, 1)
        result = self.parse_json(completed)
        contract = next(
            check for check in result["checks"] if check["id"] == "config-contract"
        )
        self.assertEqual(contract["status"], "fail")
```

- [ ] **Step 5: Run the rewritten tests and verify Nancy's real config is still red**

Run:

```bash
python3 -m unittest discover -s tests -v
python3 scripts/validate_distribution.py fast --json
```

Expected: unit fixtures pass, while validation of the repository root exits `1` because the real `config.yaml` does not yet contain `mcp_servers.chrome`.

- [ ] **Step 6: Add Chrome to Nancy's real configuration**

Insert after `terminal` and before `memory`:

```yaml
mcp_servers:
  chrome:
    url: http://browser-mcp:8080/mcp
    connect_timeout: 120
```

Do not add `xapi` or `x-docs` to Nancy.

- [ ] **Step 7: Finish repository-local validation wiring**

Append to `.gitignore`:

```gitignore

# Distribution validation reports
.hermes-validation/
```

Keep `.pre-commit-config.yaml` exactly:

```yaml
repos:
  - repo: local
    hooks:
      - id: hermes-distribution-fast
        name: Hermes distribution fast validation
        entry: python3 scripts/validate_distribution.py fast
        language: system
        pass_filenames: false
        stages: [pre-commit]
      - id: hermes-distribution-full
        name: Hermes distribution full validation
        entry: python3 scripts/validate_distribution.py full
        language: system
        pass_filenames: false
        stages: [pre-push]
```

Keep `.github/workflows/distribution.yml` on the established pinned images:

````yaml
name: Distribution validation

on:
  pull_request:
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: distribution-${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true

jobs:
  validate:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - name: Check out pull request head
        uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803
        with:
          ref: ${{ github.event.pull_request.head.sha || github.sha }}

      - name: Pull pinned validator images
        run: |
          docker pull docker.io/nousresearch/hermes-agent@sha256:dbd5484b4e822307e78bb68d5bf17a57eece7c5e278ca38b8670df9499f14731
          docker pull zricethezav/gitleaks@sha256:691af3c7c5a48b16f187ce3446d5f194838f91238f27270ed36eef6359a574d9

      - name: Run full distribution validation
        shell: bash
        run: |
          set +e
          python3 scripts/validate_distribution.py full --json --output .hermes-validation/full.json
          validator_status=$?
          set -e

          cat .hermes-validation/full.json
          {
            echo '## Hermes distribution validation'
            echo '```json'
            cat .hermes-validation/full.json
            echo '```'
          } >> "$GITHUB_STEP_SUMMARY"

          exit "$validator_status"
````

- [ ] **Step 8: Prove no Rick/X API contract remains in Nancy's tooling**

Run:

```bash
rg -n "rick|Rick|X_API_CLIENT_ID|X_API_CLIENT_SECRET|xapi|x-docs" distribution.yaml scripts tests config.yaml
```

Expected: no output and exit code `1`.

- [ ] **Step 9: Run Nancy's complete validation**

Run:

```bash
python3 -m unittest discover -s tests -v
python3 scripts/validate_distribution.py full --json
```

Expected: all unit tests pass; full JSON has `"repository":"hermes-profile-nancy"`, `"status":"pass"`, and `"exit_code":0`.

- [ ] **Step 10: Commit Nancy's distribution**

```bash
git add distribution.yaml config.yaml .gitignore .pre-commit-config.yaml
git add .github/workflows/distribution.yml scripts/validate_distribution.py
git add tests/test_validate_distribution.py
git commit -m "feat: formalize Nancy with Chrome MCP"
```

### Task 6: Document The Ownership And Enforcement Boundary

**Repository:** `rurusasu/dotfiles`

**Files:**

- Modify: `docs/hermes-agent/browser-mcp.md`

**Interfaces:**

- Consumes: `validate_chrome_mcp_sources(...)` and the canonical source config.
- Produces: operator guidance that distinguishes Hermes built-in `browser_*` tools from `mcp_servers.chrome`.

- [ ] **Step 1: Add the source contract section**

Add:

````markdown
## Distribution source contract

The root distribution and every profile declared in
`docker/hermes-agent/bootstrap-manifest.yaml` must own this exact entry in
their source `config.yaml`:

```yaml
mcp_servers:
  chrome:
    url: http://browser-mcp:8080/mcp
    connect_timeout: 120
```

Other MCP servers may coexist with `chrome`. Bootstrap stages every declared
distribution and validates this entry before synchronizing shared repositories
or opening a local transaction. It does not inject or repair configuration.

Hermes' built-in `browser_*` tools launch a separate local browser session.
For activity that must be visible through the host noVNC page, the agent must
use the tools discovered from `mcp_servers.chrome`.
````

- [ ] **Step 2: Add runtime checks**

Add:

````markdown
## Runtime verification

Use each profile home explicitly:

```bash
docker exec -e HERMES_HOME=/opt/data hermes hermes mcp test chrome
docker exec -e HERMES_HOME=/opt/data/profiles/rick hermes hermes mcp test chrome
docker exec -e HERMES_HOME=/opt/data/profiles/hoffman hermes hermes mcp test chrome
docker exec -e HERMES_HOME=/opt/data/profiles/risarisa hermes hermes mcp test chrome
docker exec -e HERMES_HOME=/opt/data/profiles/nancy hermes hermes mcp test chrome
```

Every command must report a successful connection and the same discovered
Chrome tool set, including `navigate_page` and `take_snapshot`. The host noVNC
page is `http://127.0.0.1:6080/`.
````

- [ ] **Step 3: Run documentation and bootstrap checks**

Run:

```bash
task lint:all
task hermes:bootstrap:test
```

Expected: lint succeeds; bootstrap tests end with `test_gh_wrapper: PASS`.

- [ ] **Step 4: Commit the operator documentation**

```bash
git add docs/hermes-agent/browser-mcp.md
git commit -m "docs: explain Chrome MCP profile contract"
```

### Task 7: Cross-Repository Verification And Publication Gate

**Repositories:** all five source distributions plus `rurusasu/dotfiles`

**Files:**

- Verify only; no source edits are expected.

**Interfaces:**

- Consumes: the commits from Tasks 1-6.
- Produces: a reproducible local verification record and, only after approval, publishable branches.

- [ ] **Step 1: Confirm every worktree is clean and on the intended branch**

Run `git status --short --branch` in each worktree:

```text
/Users/ktome1995/Program/dotfiles/.worktrees/hermes-chrome-all-profiles
/Users/ktome1995/Program/.worktrees/hermes-profile-rick-chrome-mcp
/Users/ktome1995/Program/.worktrees/hermes-profile-hoffman-chrome-mcp
/Users/ktome1995/Program/.worktrees/hermes-profile-risarisa-chrome-mcp
/Users/ktome1995/Program/.worktrees/hermes-profile-nancy-chrome-mcp
```

Expected: branch `codex/chrome-mcp-all-profiles` and no modified/untracked files in every worktree.

- [ ] **Step 2: Re-run every source validator**

Run in `hermes-home`:

```bash
python3 -m unittest discover -s tests -v
python3 scripts/validate_distribution.py full --json
```

Run the same two commands in the Rick, Hoffman, Risarisa, and Nancy worktrees.

Expected: all tests pass and all five full reports contain `"status":"pass"`.

- [ ] **Step 3: Re-run dotfiles verification**

Run:

```bash
task hermes:bootstrap:test
task hermes:bootstrap:config
task lint:all
```

Expected: bootstrap tests, Compose validation, and repository lint all pass.

- [ ] **Step 4: Stop for explicit publication approval**

Report the five commit SHAs, test results, and the fact that production still reads `main` from the source repositories. Do not continue to the publication and runtime tasks until the user explicitly approves push/PR/merge.

### Task 8: Publish, Apply, And Prove The Shared noVNC Session

**Precondition:** the user has explicitly approved publication.

**Repositories:** `rurusasu/hermes-profile-rick`, `rurusasu/hermes-profile-hoffman`, `rurusasu/hermes-profile-risarisa`, `rurusasu/hermes-profile-nancy`, then `rurusasu/dotfiles`.

**Files:**

- No additional edits unless CI reveals a defect.

**Interfaces:**

- Consumes: green local commits and source repositories whose `main` branches are referenced by `bootstrap-manifest.yaml`.
- Produces: merged source distributions, merged bootstrap enforcement, applied runtime state, successful MCP discovery for all profiles, and a noVNC-visible navigation proof.

- [ ] **Step 1: Push source branches and create pull requests**

For each source worktree:

```bash
git push -u origin codex/chrome-mcp-all-profiles
gh pr create --base main --head codex/chrome-mcp-all-profiles --fill
```

Expected: one pull-request URL per repository.

- [ ] **Step 2: Wait for source Actions and merge in dependency order**

For each source PR:

```bash
gh pr checks --watch
gh pr merge --squash --delete-branch
```

Expected: all checks pass and Rick, Hoffman, Risarisa, and Nancy merge before dotfiles is applied.

- [ ] **Step 3: Push, check, and merge dotfiles**

From the dotfiles worktree:

```bash
git push -u origin codex/hermes-chrome-all-profiles
gh pr create --base main --head codex/hermes-chrome-all-profiles --fill
gh pr checks --watch
gh pr merge --squash --delete-branch
```

Expected: dotfiles Actions pass and the PR merges.

- [ ] **Step 4: Update the local main checkout and apply bootstrap**

From `/Users/ktome1995/Program/dotfiles`:

```bash
git pull --ff-only origin main
task hermes:bootstrap
```

Expected: bootstrap reports `status: applied`; root plus profiles `rick`, `hoffman`, `risarisa`, and `nancy` are installed without validation errors.

- [ ] **Step 5: Test Chrome MCP from every runtime home**

Run:

```bash
docker exec -e HERMES_HOME=/opt/data hermes hermes mcp test chrome
docker exec -e HERMES_HOME=/opt/data/profiles/rick hermes hermes mcp test chrome
docker exec -e HERMES_HOME=/opt/data/profiles/hoffman hermes hermes mcp test chrome
docker exec -e HERMES_HOME=/opt/data/profiles/risarisa hermes hermes mcp test chrome
docker exec -e HERMES_HOME=/opt/data/profiles/nancy hermes hermes mcp test chrome
```

Expected: each command connects to `http://browser-mcp:8080/mcp` and discovers the same Chrome MCP tools, including `navigate_page` and `take_snapshot`.

- [ ] **Step 6: Trigger a Nancy-only MCP navigation proof**

Record the start time in the shell that will run Steps 6 and 7:

```bash
export START_EPOCH="$(date +%s)"
printf '%s\n' "$START_EPOCH"
```

Then run:

```bash
docker exec -e HERMES_HOME=/opt/data/profiles/nancy hermes hermes -z "Use the Chrome MCP navigate_page tool, not any built-in browser_* tool, to open https://example.com/?profile=nancy. Report only the final page title."
```

Expected: final response `Example Domain`.

- [ ] **Step 7: Verify the recorded tool call came from Chrome MCP**

Run in the same shell:

```bash
docker exec -e START_EPOCH="$START_EPOCH" hermes python -c "import os, sqlite3; db=sqlite3.connect('/opt/data/profiles/nancy/state.db'); print(list(db.execute(\"select tool_name from messages where timestamp >= ? and role = 'tool' order by id\", (float(os.environ['START_EPOCH']),))))"
```

Expected: the output contains the Chrome MCP navigation tool name and contains neither `browser_navigate` nor `browser_snapshot`.

- [ ] **Step 8: Verify the same navigation in noVNC**

Open `http://127.0.0.1:6080/` in the connected Browser plugin.

Expected: the visible Chromium session shows `Example Domain` at `https://example.com/?profile=nancy`, proving Nancy used the shared `hermes-chromium` session rather than a separate built-in headless browser.

- [ ] **Step 9: Report final evidence**

Report:

- Source and dotfiles PR URLs.
- Green Actions status.
- Bootstrap apply result.
- Five successful `mcp test chrome` results.
- Nancy's recorded MCP tool name.
- noVNC page title and URL.
