#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "default test task runs the POSIX suite on macOS and Linux" {
	command -v task >/dev/null 2>&1 || skip "task is not available in this test environment"

	run task --dir "$REPO_ROOT" --dry test DOTFILES_PATH="$REPO_ROOT"

	[ "$status" -eq 0 ]
	[[ "$output" == *"bats tests/bash"* ]]
	[[ "$output" != *"Invoke-Tests.ps1"* ]]
}
