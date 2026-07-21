# Bootstrap Core Task 1 Report

## Scope

- Added the non-secret Hermes bootstrap manifest.
- Added immutable manifest domain models, stable bootstrap error classes, and strict YAML validation.
- Added deterministic `unittest` coverage for approved declarations and every requested validation case.

## TDD Evidence

- RED: `python3 -m unittest docker/hermes-agent/bootstrap/tests/test_manifest.py -v` failed with `ModuleNotFoundError: No module named 'hermes_bootstrap'` before implementation.
- Host prerequisite: `python3 -c 'import yaml; print(yaml.__version__)'` failed with `ModuleNotFoundError: No module named 'yaml'`. The subsequent direct host unittest command therefore also stopped at the missing PyYAML dependency; no dependency was added or vendored.
- GREEN authoritative container run:

  ```sh
  docker run --rm -v "$PWD:/workspace:ro" -w /workspace --entrypoint sh \
    docker.io/nousresearch/hermes-agent@sha256:dbd5484b4e822307e78bb68d5bf17a57eece7c5e278ca38b8670df9499f14731 \
    -c 'PYTHONPATH=/workspace/docker/hermes-agent/bootstrap python3 -m unittest docker/hermes-agent/bootstrap/tests/test_manifest.py -v'
  ```

  Result: 17 tests passed.

## Independent-Review Hardening

- Profile targets now resolve exactly to `/opt/data/profiles/<profile name>` and shared repositories to `/opt/data/shared/<repository name>`.
- Non-root canonical targets cannot collide or overlap. Legacy targets cannot be the data root or collide with canonical or other legacy targets.
- Git refs now apply the `git check-ref-format` component restrictions while retaining `main` and normal slash-separated refs.
- Manifest loading normalizes invalid UTF-8 to `ValidationError` and rejects duplicate YAML keys at every mapping depth with a `SafeLoader` subclass.

## TDD Evidence: Independent-Review Fixes

- RED: the fixed-image test command below initially reported 16 failures and 1 error. The failures covered target namespace and collision checks plus the missing Git ref component rules; the error was an uncaught `UnicodeDecodeError`.
- RED: after tightening duplicate-key cases to use otherwise-valid JSON-as-YAML documents, the isolated top-level and nested duplicate-key tests each failed because `yaml.safe_load` retained the later value.
- GREEN: the same fixed-image manifest test command passed all 26 tests after the minimal loader and validation changes.

  ```sh
  docker run --rm -v "$PWD:/workspace:ro" -w /workspace --entrypoint sh \
    docker.io/nousresearch/hermes-agent@sha256:dbd5484b4e822307e78bb68d5bf17a57eece7c5e278ca38b8670df9499f14731 \
    -c 'PYTHONPATH=/workspace/docker/hermes-agent/bootstrap python3 -m unittest docker/hermes-agent/bootstrap/tests/test_manifest.py -v'
  ```

## Verification

- Host `python3 -m py_compile docker/hermes-agent/bootstrap/hermes_bootstrap/manifest.py docker/hermes-agent/bootstrap/tests/test_manifest.py` passed.
- Pinned-image full bootstrap test discovery passed all 26 tests.
- Pinned-image approved-manifest parsing passed and reported `1 /opt/data 6 3 1` for schema version, data root, 1Password declarations, profiles, and shared repositories.
- Secret-pattern scan for common Slack, GitHub, OpenAI, and AWS token formats reported no matches.
- `git diff --check` reported no whitespace errors.
- Final HEAD: `fix: harden Hermes bootstrap manifest validation` (this report is included in that commit; its resolved SHA is reported with the completed work).
