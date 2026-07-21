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

## Verification

- Host `python3 -m py_compile` passed for all Task 1 Python files.
- Pinned-image manifest parse passed and reported `1 /opt/data 6 3 1` for schema version, data root, 1Password declarations, profiles, and shared repositories.
- Secret-pattern scan for common Slack, GitHub, and OpenAI token formats reported no matches.
- `git diff --check` will be repeated against the staged Task 1 files immediately before commit.
