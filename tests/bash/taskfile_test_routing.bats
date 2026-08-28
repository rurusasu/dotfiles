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

@test "quality and commit tasks target the active root on Unix" {
	command -v task >/dev/null 2>&1 || skip "task is not available"
	run task --dir "$REPO_ROOT" --dry commit -- "test commit"
	[ "$status" -eq 0 ]
	[[ "$output" == *"cd $REPO_ROOT && nix fmt"* ]]
	[[ "$output" == *"cd $REPO_ROOT && pre-commit run --all-files"* ]]
	[[ "$output" == *"cd $REPO_ROOT && git add -A"* ]]
	[[ "$output" != *'cd ~/.dotfiles'* ]]
}

@test "commit task removes shell quoting from the commit subject" {
	command -v task >/dev/null 2>&1 || skip "task is not available"

	fixture="$(mktemp -d)"
	cat > "$fixture/Taskfile.yml" <<EOF
version: "3"
vars:
  DOTFILES_PATH: "$fixture"
  WSL: ""
includes:
  git:
    taskfile: "$REPO_ROOT/taskfiles/git/taskfile.yml"
    flatten: true
tasks:
  skills:sync:
    cmds: ["true"]
  fmt:
    cmds: ["true"]
  lint:
    cmds: ["true"]
EOF
	git -C "$fixture" init -q
	git -C "$fixture" config user.name "Bats Test"
	git -C "$fixture" config user.email "bats@example.invalid"
	touch "$fixture/fixture"
	git -C "$fixture" add fixture
	git -C "$fixture" commit -qm "initial"

	run task --dir "$fixture" --taskfile "$fixture/Taskfile.yml" commit -- "chore(nix): update flake inputs for Darwin packages"
	[ "$status" -eq 0 ]
	run git -C "$fixture" log -1 --format=%s
	[ "$output" = "chore(nix): update flake inputs for Darwin packages" ]
}

@test "root Taskfile composes feature taskfiles without renaming public tasks" {
	command -v task >/dev/null 2>&1 || skip "task is not available in this test environment"

	for feature in quality sync git nix dev test install docker hermes hooks; do
		[ -f "$REPO_ROOT/taskfiles/$feature/taskfile.yml" ]
		grep -Fq "taskfiles/$feature/taskfile.yml" "$REPO_ROOT/Taskfile.yml"
		grep -Fq "flatten: true" "$REPO_ROOT/Taskfile.yml"
	done

	run task --dir "$REPO_ROOT" --list
	[ "$status" -eq 0 ]
	[[ "$output" == *"hermes:up"* ]]
	[[ "$output" == *"hermes:xapi:auth"* ]]
	[[ "$output" == *"hermes:xapi:setup"* ]]
	[[ "$output" == *"hermes:xapi:sync-token"* ]]
	[[ "$output" == *"nrs"* ]]
	[[ "$output" == *"test:bash"* ]]
}

@test "xapi token sync task uses the platform adapter" {
	command -v task >/dev/null || skip "go-task is unavailable"

	run task --dir "$REPO_ROOT" --dry hermes:xapi:sync-token

	[ "$status" -eq 0 ]
	[[ "$output" == *"scripts/sh/hermes-xapi.sh sync-token"* ]]
}

@test "xapi setup runs auth, token sync, and restart in order" {
	command -v task >/dev/null || skip "go-task is unavailable"

	run task --dir "$REPO_ROOT" --dry --force hermes:xapi:setup

	[ "$status" -eq 0 ]
	auth_line="$(grep -n 'task: \[hermes:xapi:auth\]' <<<"$output" | cut -d: -f1)"
	sync_line="$(grep -n 'task: \[hermes:xapi:sync-token\]' <<<"$output" | cut -d: -f1)"
	restart_line="$(grep -n 'task: \[hermes:xapi:restart\]' <<<"$output" | cut -d: -f1)"
	[ -n "$auth_line" ]
	[ -n "$sync_line" ]
	[ -n "$restart_line" ]
	[ "$auth_line" -lt "$sync_line" ]
	[ "$sync_line" -lt "$restart_line" ]
}

@test "nrs orders rebuild, profile activation, and Hermes bootstrap" {
	command -v task >/dev/null || skip "go-task is unavailable"

	run task --dir "$REPO_ROOT" --dry --force nrs

	[ "$status" -eq 0 ]
	rebuild_line="$(grep -n 'nix flake update && sudo nixos-rebuild switch' <<<"$output" | cut -d: -f1)"
	profile_line="$(grep -n "nix profile upgrade '.*'" <<<"$output" | cut -d: -f1)"
	bootstrap_line="$(grep -n 'task: \[hermes:bootstrap\]' <<<"$output" | cut -d: -f1)"
	[ -n "$rebuild_line" ]
	[ -n "$profile_line" ]
	[ -n "$bootstrap_line" ]
	[ "$rebuild_line" -lt "$profile_line" ]
	[ "$profile_line" -lt "$bootstrap_line" ]
}

@test "Hermes restart reuses the xapi-aware up task" {
	command -v task >/dev/null || skip "go-task is unavailable"

	run task --dir "$REPO_ROOT" --dry --force hermes:restart

	[ "$status" -eq 0 ]
	[[ "$output" == *"task: [hermes:up]"* ]]
	[[ "$output" == *"scripts/sh/hermes-xapi.sh up"* ]]
}
