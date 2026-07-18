#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "chezmoi shell scripts use a PATH-portable bash shebang" {
	run rg -n '^#!/bin/bash$' "$REPO_ROOT/chezmoi/.chezmoiscripts" -g '*.sh.tmpl'

	[ "$status" -eq 1 ]
	[ -z "$output" ]
}
