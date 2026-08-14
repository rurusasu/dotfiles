#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	WEZTERM_CONFIG="$REPO_ROOT/chezmoi/terminals/wezterm/wezterm.lua"
}

@test "WezTerm workspace picker resolves without fuzzy filtering" {
	command -v wezterm >/dev/null

	run wezterm --config-file "$WEZTERM_CONFIG" show-keys --lua
	[ "$status" -eq 0 ]

	workspace_binding="$(printf '%s\n' "$output" | grep "key = 'w'.*mods = 'LEADER'.*ShowLauncherArgs")"
	[[ "$workspace_binding" == *"flags =  'WORKSPACES'"* ]]
	[[ "$workspace_binding" != *"FUZZY"* ]]
}

@test "WezTerm effective window-manager actions exist only behind the leader" {
	command -v wezterm >/dev/null

	run wezterm --config-file "$WEZTERM_CONFIG" show-keys --lua
	[ "$status" -eq 0 ]

	contract_external_bindings="$(printf '%s\n' "$output" | awk '
		/action = act\.(SpawnTab|CloseCurrentTab|ActivateTab|MoveTabRelative|SplitHorizontal|SplitVertical|ActivatePaneDirection|CloseCurrentPane)/ &&
		$0 !~ /mods = '\''[^'\'']*LEADER/ { print }
	')"
	[ -z "$contract_external_bindings" ]

	[[ "$output" == *"mods = 'SUPER', action = act.CopyTo 'Clipboard'"* ]]
	[[ "$output" == *"mods = 'SUPER', action = act.PasteFrom 'Clipboard'"* ]]
	[[ "$output" == *"mods = 'SUPER', action = act.Search 'CurrentSelectionOrEmptyString'"* ]]
	[[ "$output" == *"mods = 'SHIFT|CTRL', action = act.IncreaseFontSize"* ]]
	[[ "$output" == *"key = 'F11', mods = 'NONE', action = act.ToggleFullScreen"* ]]
	[[ "$output" == *"key = 'h', mods = 'ALT|SUPER', action = act.EmitEvent"* ]]
	[[ "$output" == *"key = 'l', mods = 'ALT|SUPER', action = act.EmitEvent"* ]]
}
