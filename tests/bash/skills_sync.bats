#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	TEST_HOME="$BATS_TEST_TMPDIR/home"
	SYNC_SCRIPT="$BATS_TEST_TMPDIR/sync-agent-skills.sh"
	mkdir -p "$TEST_HOME/.agents/skills/current" "$TEST_HOME/.claude/skills/legacy-directory"
	printf 'managed\n' >"$TEST_HOME/.agents/skills/current/SKILL.md"
	printf 'legacy\n' >"$TEST_HOME/.claude/skills/legacy-directory/SKILL.md"
	chezmoi execute-template --source "$REPO_ROOT/chezmoi" \
		<"$REPO_ROOT/chezmoi/.chezmoiscripts/run_after_sync-agent-skills_linux.sh.tmpl" \
		>"$SYNC_SCRIPT"
	chmod +x "$SYNC_SCRIPT"
}

@test "agent skill sync removes directory and dangling orphan symlinks" {
	mkdir -p "$TEST_HOME/.codex/skills"
	ln -s "$TEST_HOME/.claude/skills/legacy-directory" "$TEST_HOME/.codex/skills/legacy-directory"
	ln -s "$TEST_HOME/.claude/skills/missing" "$TEST_HOME/.codex/skills/legacy-dangling"

	run env HOME="$TEST_HOME" "$SYNC_SCRIPT"

	[ "$status" -eq 0 ]
	[ ! -e "$TEST_HOME/.codex/skills/legacy-directory" ]
	[ ! -L "$TEST_HOME/.codex/skills/legacy-directory" ]
	[ ! -L "$TEST_HOME/.codex/skills/legacy-dangling" ]
	[ -L "$TEST_HOME/.codex/skills/current" ]
	[ "$(readlink "$TEST_HOME/.codex/skills/current")" = "$TEST_HOME/.agents/skills/current" ]
}
