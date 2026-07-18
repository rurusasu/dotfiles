#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "chezmoi shell scripts use a PATH-portable bash shebang" {
	violations="$(
		find "$REPO_ROOT/chezmoi/.chezmoiscripts" -type f -name '*.sh.tmpl' \
			-exec grep -Hn '^#!/bin/bash$' {} + || true
	)"

	[ -z "$violations" ]
}
