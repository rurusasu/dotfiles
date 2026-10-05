#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	PATHS_FILE="$BATS_TEST_TMPDIR/changed-paths.txt"
}

# Routing combinations are covered in tests/python/test_detect_ci_changes.py.
# Keep these smoke tests focused on the executable CLI and JSON output contract.
assert_enabled_outputs() {
	python3 -c '
import json
import sys

outputs = json.loads(sys.argv[1])
assert isinstance(outputs, dict), outputs
assert all(type(enabled) is bool for enabled in outputs.values()), outputs
assert {name for name, enabled in outputs.items() if enabled} == set(sys.argv[2:]), outputs
' "$output" "$@"
}

@test "CI routing CLI reads paths with the default manifest and emits JSON" {
	printf '%s\n' "scripts/sh/install-linux.sh" >"$PATHS_FILE"
	run python3 "$REPO_ROOT/scripts/python/detect_ci_changes.py" --paths-file "$PATHS_FILE"
	[ "$status" -eq 0 ]
	assert_enabled_outputs contract linux
}

@test "CI routing CLI reads paths with an explicit bootstrap manifest and emits JSON" {
	printf '%s\n' "windows/winget/packages.json" >"$PATHS_FILE"
	run python3 "$REPO_ROOT/scripts/python/detect_ci_changes.py" \
		--manifest "$REPO_ROOT/ci/bootstrap-path-routing.json" \
		--paths-file "$PATHS_FILE"
	[ "$status" -eq 0 ]
	assert_enabled_outputs contract windows
}
