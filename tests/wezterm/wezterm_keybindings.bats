#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	WEZTERM_CONFIG="$REPO_ROOT/chezmoi/terminals/wezterm/wezterm.lua"
}

@test "WezTerm nested leader forwards Ctrl+Space while Ctrl remains held" {
	command -v wezterm >/dev/null

	run wezterm --config-file "$WEZTERM_CONFIG" show-keys --lua
	[ "$status" -eq 0 ]

	nested_leader_binding="$(printf '%s\n' "$output" | grep "key = 'phys:Space'.*mods = 'CTRL|LEADER'.*SendKey.*key =  'Space'.*mods =  'CTRL'")"
	[ -n "$nested_leader_binding" ]
}

@test "WezTerm workspace picker resolves without fuzzy filtering" {
	command -v wezterm >/dev/null

	run wezterm --config-file "$WEZTERM_CONFIG" show-keys --lua
	[ "$status" -eq 0 ]

	workspace_binding="$(printf '%s\n' "$output" | grep "key = 'w'.*mods = 'LEADER'.*ShowLauncherArgs")"
	[[ "$workspace_binding" == *"flags =  'WORKSPACES'"* ]]
	[[ "$workspace_binding" != *"FUZZY"* ]]
}

@test "WezTerm effective window-manager actions use only approved bindings" {
	command -v wezterm >/dev/null

	run wezterm --config-file "$WEZTERM_CONFIG" show-keys --lua
	[ "$status" -eq 0 ]

	contract_external_bindings="$(printf '%s\n' "$output" | awk '
		/action = act\.(SpawnTab|CloseCurrentTab|ActivateTab|MoveTabRelative|SplitHorizontal|SplitVertical|ActivatePaneDirection|CloseCurrentPane)/ &&
		$0 !~ /mods = '\''[^'\'']*LEADER/ { print }
	')"
	[ -z "$contract_external_bindings" ]

	zoom_bindings="$(printf '%s\n' "$output" | grep 'action = act.TogglePaneZoomState')"
	[ "$(printf '%s\n' "$zoom_bindings" | wc -l | tr -d ' ')" -eq 1 ]
	[[ "$zoom_bindings" == *"key = 'w', mods = 'ALT|CTRL'"* ]]

	resize_bindings="$(printf '%s\n' "$output" | grep 'action = act.AdjustPaneSize')"
	[ "$(printf '%s\n' "$resize_bindings" | wc -l | tr -d ' ')" -eq 4 ]
	[ -z "$(printf '%s\n' "$resize_bindings" | grep -v "mods = 'CTRL|SUPER'")" ]

	[[ "$output" == *"mods = 'SUPER', action = act.CopyTo 'Clipboard'"* ]]
	[[ "$output" == *"mods = 'SUPER', action = act.PasteFrom 'Clipboard'"* ]]
	[[ "$output" == *"mods = 'SUPER', action = act.Search 'CurrentSelectionOrEmptyString'"* ]]
	[[ "$output" == *"mods = 'SHIFT|CTRL', action = act.IncreaseFontSize"* ]]
	[[ "$output" == *"key = 'F11', mods = 'NONE', action = act.ToggleFullScreen"* ]]
	[[ "$output" == *"key = 'h', mods = 'ALT|SUPER', action = act.EmitEvent"* ]]
	[[ "$output" == *"key = 'l', mods = 'ALT|SUPER', action = act.EmitEvent"* ]]
}
