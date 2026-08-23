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

@test "Claude marketplace installers recover invalid checkouts" {
	for template in \
		"$REPO_ROOT/chezmoi/.chezmoiscripts/run_always_install-claude-plugins_darwin.sh.tmpl" \
		"$REPO_ROOT/chezmoi/.chezmoiscripts/run_always_install-claude-plugins_linux.sh.tmpl"; do
		grep -Fq 'git -C "$TARGET_DIR" rev-parse --is-inside-work-tree' "$template"
		grep -Fq 'mktemp -d' "$template"
		grep -Fq '.invalid.$(date +%Y%m%d%H%M%S)' "$template"
	done

	windows_template="$REPO_ROOT/chezmoi/.chezmoiscripts/run_always_install-claude-plugins_windows.ps1.tmpl"
	grep -Fq 'rev-parse --is-inside-work-tree' "$windows_template"
	grep -Fq '.invalid.$(Get-Date -Format yyyyMMddHHmmss)' "$windows_template"
}
