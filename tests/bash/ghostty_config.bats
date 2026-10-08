#!/usr/bin/env bats
setup() {
	REPO_ROOT="${GHOSTTY_TEST_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"
	mkdir -p "$BATS_TEST_TMPDIR/home"
	export HOME="$BATS_TEST_TMPDIR/home"
}
@test "chezmoi has no Unix terminal deployment and no Ghostty source" {
	[ ! -e "$REPO_ROOT/chezmoi/.chezmoiscripts/deploy/terminals/run_onchange_deploy.sh.tmpl" ]
	[ ! -e "$REPO_ROOT/chezmoi/terminals/ghostty/config" ]
}
@test "Windows deploy template reads rendered WezTerm Lua only on Windows" {
	for os in linux darwin windows; do
		rendered=$(chezmoi --config /dev/null --config-format toml --source "$REPO_ROOT/chezmoi" \
			--destination "$HOME" --cache "$BATS_TEST_TMPDIR/cache" --persistent-state "$BATS_TEST_TMPDIR/state.boltdb" \
			--override-data "{\"chezmoi\":{\"os\":\"$os\"}}" execute-template \
			--file "$REPO_ROOT/chezmoi/.chezmoiscripts/deploy/terminals/run_onchange_deploy.ps1.tmpl")
		if [[ $os == windows ]]; then
			[[ $rendered == *'local wezterm = require("wezterm")'* ]]
			[[ $rendered == *'Deploy-Content $WezTermConfig'* ]]
			[[ $rendered != *'{{ .appearance.'* ]]
		else
			[ -z "$rendered" ]
		fi
	done
}
@test "chezmoi excludes the Windows WezTerm launcher on Unix" {
	for os in linux darwin windows; do
		managed=$(chezmoi --config /dev/null --config-format toml --source "$REPO_ROOT/chezmoi" \
			--destination "$HOME" --cache "$BATS_TEST_TMPDIR/cache" --persistent-state "$BATS_TEST_TMPDIR/state.boltdb" \
			--override-data "{\"chezmoi\":{\"os\":\"$os\"}}" managed --include files --path-style relative)
		if [[ $os == windows ]]; then
			[[ $managed == *'.local/bin/wezterm-launch.cmd'* ]]
		else
			[[ $managed != *'.local/bin/wezterm-launch.cmd'* ]]
			[[ $managed != *'.config/wezterm/'* ]]
			[[ $managed != *'.config/ghostty/'* ]]
		fi
	done
}
