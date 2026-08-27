#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "Home Manager uses the canonical flat OS module layout" {
	test -f "$REPO_ROOT/nix/home/README.md"
	test -f "$REPO_ROOT/nix/home/common.nix"
	test -f "$REPO_ROOT/nix/home/darwin.nix"
	test -f "$REPO_ROOT/nix/home/linux.nix"
	test -f "$REPO_ROOT/nix/home/wsl.nix"
	test ! -e "$REPO_ROOT/nix/home/default.nix"
	test ! -e "$REPO_ROOT/nix/home/users"
}

@test "OS-specific Home Manager modules import only the shared module" {
	grep -Fq 'imports = [ ./common.nix ];' "$REPO_ROOT/nix/home/darwin.nix"
	grep -Fq 'imports = [ ./common.nix ];' "$REPO_ROOT/nix/home/linux.nix"
	grep -Fq 'imports = [ ./common.nix ];' "$REPO_ROOT/nix/home/wsl.nix"
}

@test "the shared Home Manager module does not import an OS-specific module" {
	! grep -Eq '^[[:space:]]*(import|imports)[[:space:]=].*(darwin|linux|wsl)\.nix' "$REPO_ROOT/nix/home/common.nix"
}
