#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "README documents all bootstrap entrypoints and reruns" {
	grep -q 'install.cmd' "$REPO_ROOT/README.md"
	[ "$(grep -c './install.sh' "$REPO_ROOT/README.md")" -ge 2 ]
	grep -q 'DOTFILES_ALLOW_USER_ONLY=1' "$REPO_ROOT/README.md"
	grep -Eqi 're-run|rerun|再実行' "$REPO_ROOT/README.md"
	grep -q 'self-hosted-bootstrap-runners.md' "$REPO_ROOT/README.md"
}

@test "architecture documents the four declarative layers" {
	grep -q 'nix-darwin' "$REPO_ROOT/docs/architecture.md"
	grep -q 'System Manager' "$REPO_ROOT/docs/architecture.md"
	grep -q 'NixOS' "$REPO_ROOT/docs/architecture.md"
	grep -q 'winget' "$REPO_ROOT/docs/architecture.md"
	grep -q 'runtime acceptance' "$REPO_ROOT/docs/architecture.md"
}

@test "package and PowerShell docs describe generated coverage and acceptance" {
	grep -q 'package-support-report' "$REPO_ROOT/docs/nix/package-management.md"
	grep -q 'Test-Environment.ps1' "$REPO_ROOT/docs/scripts/powershell/testing.md"
	grep -q 'hello-world' "$REPO_ROOT/docs/scripts/powershell/testing.md"
}
