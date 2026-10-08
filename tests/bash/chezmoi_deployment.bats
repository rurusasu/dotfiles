#!/usr/bin/env bats

@test "chezmoi deploys only Codex and Claude on Unix while preserving Windows targets" {
	command -v chezmoi >/dev/null 2>&1 || skip "chezmoi is required"
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	source_dir="$BATS_TEST_TMPDIR/source"
	cp -R "$REPO_ROOT/chezmoi" "$source_dir"
	# Exercise future Claude settings and Windows targets, not just existing files.
	mkdir -p "$source_dir/dot_claude" "$source_dir/dot_future-windows"
	printf '{}\n' >"$source_dir/dot_claude/settings.json"
	printf 'Windows only\n' >"$source_dir/dot_future-windows/config"

	for os in linux darwin windows; do
		destination="$BATS_TEST_TMPDIR/$os/home"
		mkdir -p "$destination"
		chezmoi_args=(
			--config /dev/null --config-format toml
			--source "$source_dir" --destination "$destination"
			--cache "$BATS_TEST_TMPDIR/$os/cache"
			--persistent-state "$BATS_TEST_TMPDIR/$os/state.boltdb"
			--override-data "{\"chezmoi\":{\"os\":\"$os\",\"homeDir\":\"$destination\"}}"
		)
		run chezmoi "${chezmoi_args[@]}" managed --path-style relative
		[ "$status" -eq 0 ]
		[[ "$output" == *'.codex/config.toml'* ]]
		[[ "$output" == *'.claude/settings.json'* ]]
		if [ "$os" = windows ]; then
			[[ "$output" == *'.config/shell/secret.ps1'* ]]
			[[ "$output" == *'.gemini/settings.json'* ]]
			[[ "$output" == *'.future-windows/config'* ]]
			run chezmoi "${chezmoi_args[@]}" managed --include scripts
			[ "$status" -eq 0 ]
			[[ "$output" == *'.chezmoiscripts/deploy/shells/deploy.ps1'* ]]
		else
			[[ "$output" == *'.codex/AGENTS.override.md'* ]]
			while IFS= read -r target; do
				case "$target" in
				.codex | .codex/* | .claude | .claude/*) ;;
				*) return 1 ;;
				esac
			done <<<"$output"
			run chezmoi "${chezmoi_args[@]}" managed --include scripts
			[ "$status" -eq 0 ]
			[ -z "$output" ]
		fi
		# Render only the command-policy hooks in the isolated test home.
		mkdir -p "$destination/.codex"
		run chezmoi "${chezmoi_args[@]}" apply --exclude scripts --force -- \
			"$destination/.codex/hooks.json"
		[ "$status" -eq 0 ]
		jq -e '.hooks.PreToolUse[0].hooks | length == 2' "$destination/.codex/hooks.json"
	done
}
