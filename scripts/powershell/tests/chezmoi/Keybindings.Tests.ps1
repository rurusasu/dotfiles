#Requires -Module Pester

BeforeAll {
    $script:repoRoot = Resolve-Path (Join-Path $PSScriptRoot "../../../..")
    $script:chezmoiRoot = Join-Path $script:repoRoot "chezmoi"

    function Get-JsonContent {
        param([string]$Path)
        Get-Content -LiteralPath (Join-Path $script:repoRoot $Path) -Raw | ConvertFrom-Json
    }

    function Get-WindowsTerminalCommandForKey {
        param(
            [Parameter(Mandatory)]
            $Settings,
            [Parameter(Mandatory)]
            [string]$Keys
        )

        $binding = @($Settings.keybindings | Where-Object { $_.keys -eq $Keys }) | Select-Object -First 1
        if (-not $binding) { return $null }

        $inlineCommand = $binding.PSObject.Properties["command"]
        if ($inlineCommand) { return $inlineCommand.Value }

        $idProperty = $binding.PSObject.Properties["id"]
        if (-not $idProperty) { return $null }
        $id = $idProperty.Value
        if (-not $id) { return $null }

        $action = @($Settings.actions | Where-Object { $_.id -eq $id }) | Select-Object -First 1
        if (-not $action) { return $null }

        return $action.command
    }

    function Assert-WindowsTerminalDirectionalAction {
        param(
            [Parameter(Mandatory)]
            $Settings,
            [Parameter(Mandatory)]
            [string]$Keys,
            [Parameter(Mandatory)]
            [string]$Action,
            [Parameter(Mandatory)]
            [string]$Direction
        )

        $command = Get-WindowsTerminalCommandForKey -Settings $Settings -Keys $Keys
        $command | Should -Not -BeNullOrEmpty -Because "$Keys should be bound"
        $command.action | Should -Be $Action -Because "$Keys should use $Action"
        $command.direction | Should -Be $Direction -Because "$Keys should point $Direction"
    }

    function Assert-KeyCommand {
        param(
            [Parameter(Mandatory)]
            $Bindings,
            [Parameter(Mandatory)]
            [string]$Key,
            [Parameter(Mandatory)]
            [string]$Command
        )

        $binding = @($Bindings | Where-Object { $_.key -eq $Key -and $_.command -eq $Command }) | Select-Object -First 1
        $binding | Should -Not -BeNullOrEmpty -Because "$Key should run $Command"
    }

    function Get-ZedWorkspaceBinding {
        $zed = Get-JsonContent "chezmoi/editors/zed/keymap.json"
        $workspace = @($zed | Where-Object { $_.context -eq "Workspace" }) | Select-Object -First 1
        $workspace | Should -Not -BeNullOrEmpty
        return $workspace.bindings
    }
}

Describe '標準キーバインド方針' {
    It 'docs は GUI と Unix/Vim 系の標準レイヤーを明示すること' {
        $docs = Get-Content -LiteralPath (Join-Path $script:repoRoot "docs/chezmoi/keybindings.md") -Raw

        $docs | Should -Match 'Command\+D' -Because "macOS WezTerm should use the standard split shortcut"
        $docs | Should -Match 'Command\+Shift\+D' -Because "macOS WezTerm should provide the second standard split shortcut"
        $docs | Should -Match 'Leader.*WezTerm' -Because "macOS WezTerm navigation should keep the leader"
        $docs | Should -Match 'Ctrl\+Space' -Because "macOS WezTerm leader should be Ctrl+Space"
        $docs | Should -Match 'Leader.*pane' -Because "macOS WezTerm leader should control panes"
        $docs | Should -Match 'Alt\+H/J/K/L' -Because "other GUI editors should keep Alt focus"
        $docs | Should -Match 'Ctrl\+H/J/K/L' -Because "Unix/Vim/tmux focus should keep the standard Ctrl+H/J/K/L layer"
    }

    It 'Windows Terminal は Alt 矢印 focus, Alt+Shift swap/resize に揃えること' {
        $settings = Get-JsonContent "chezmoi/terminals/windows-terminal/settings.json"

        Assert-WindowsTerminalDirectionalAction $settings "alt+left" "moveFocus" "left"
        Assert-WindowsTerminalDirectionalAction $settings "alt+down" "moveFocus" "down"
        Assert-WindowsTerminalDirectionalAction $settings "alt+up" "moveFocus" "up"
        Assert-WindowsTerminalDirectionalAction $settings "alt+right" "moveFocus" "right"

        Assert-WindowsTerminalDirectionalAction $settings "alt+shift+h" "swapPane" "left"
        Assert-WindowsTerminalDirectionalAction $settings "alt+shift+j" "swapPane" "down"
        Assert-WindowsTerminalDirectionalAction $settings "alt+shift+k" "swapPane" "up"
        Assert-WindowsTerminalDirectionalAction $settings "alt+shift+l" "swapPane" "right"

        Assert-WindowsTerminalDirectionalAction $settings "alt+shift+left" "resizePane" "left"
        Assert-WindowsTerminalDirectionalAction $settings "alt+shift+down" "resizePane" "down"
        Assert-WindowsTerminalDirectionalAction $settings "alt+shift+up" "resizePane" "up"
        Assert-WindowsTerminalDirectionalAction $settings "alt+shift+right" "resizePane" "right"
    }

    It 'WezTerm は macOS だけ Command、他 OS は従来の Alt で pane 操作を行うこと' {
        $content = Get-Content -LiteralPath (Join-Path $script:chezmoiRoot "terminals/wezterm/wezterm.lua") -Raw

        $content | Should -Match '\{ key = "d", mods = "SUPER", action = act\.SplitHorizontal'
        $content | Should -Match '\{ key = "d", mods = "SUPER\|SHIFT", action = act\.SplitVertical'
        $content | Should -Match '\{ key = "\+", mods = "ALT\|SHIFT", action = act\.SplitHorizontal'
        $content | Should -Match '\{ key = "-", mods = "ALT\|SHIFT", action = act\.SplitVertical'
        $content | Should -Match '\{ key = "LeftArrow", mods = "LEADER", action = act\.ActivatePaneDirection\("Left"\) \}'
        $content | Should -Match '\{ key = "UpArrow", mods = "LEADER", action = act\.ActivatePaneDirection\("Up"\) \}'
        $content | Should -Match '\{ key = "RightArrow", mods = "LEADER", action = act\.ActivatePaneDirection\("Right"\) \}'
        $content | Should -Match '\{ key = "DownArrow", mods = "LEADER", action = act\.ActivatePaneDirection\("Down"\) \}'

        $content | Should -Match '\{ key = "LeftArrow", mods = "ALT", action = act\.ActivatePaneDirection\("Left"\) \}'
        $content | Should -Match '\{ key = "UpArrow", mods = "ALT", action = act\.ActivatePaneDirection\("Up"\) \}'
        $content | Should -Match '\{ key = "RightArrow", mods = "ALT", action = act\.ActivatePaneDirection\("Right"\) \}'
        $content | Should -Match '\{ key = "DownArrow", mods = "ALT", action = act\.ActivatePaneDirection\("Down"\) \}'

        $content | Should -Match '\{ key = "LeftArrow", mods = "LEADER\|SHIFT", action = act\.AdjustPaneSize\(\{ "Left", 5 \}\) \}'
        $content | Should -Match '\{ key = "UpArrow", mods = "LEADER\|SHIFT", action = act\.AdjustPaneSize\(\{ "Up", 5 \}\) \}'
        $content | Should -Match '\{ key = "RightArrow", mods = "LEADER\|SHIFT", action = act\.AdjustPaneSize\(\{ "Right", 5 \}\) \}'
        $content | Should -Match '\{ key = "DownArrow", mods = "LEADER\|SHIFT", action = act\.AdjustPaneSize\(\{ "Down", 5 \}\) \}'

        $content | Should -Match '\{ key = "LeftArrow", mods = "ALT\|SHIFT", action = act\.AdjustPaneSize\(\{ "Left", 5 \}\) \}'
        $content | Should -Match '\{ key = "UpArrow", mods = "ALT\|SHIFT", action = act\.AdjustPaneSize\(\{ "Up", 5 \}\) \}'
        $content | Should -Match '\{ key = "RightArrow", mods = "ALT\|SHIFT", action = act\.AdjustPaneSize\(\{ "Right", 5 \}\) \}'
        $content | Should -Match '\{ key = "DownArrow", mods = "ALT\|SHIFT", action = act\.AdjustPaneSize\(\{ "Down", 5 \}\) \}'

        $content | Should -Match '\{ key = "h", mods = "LEADER", action = focus_adjacent_window\("left"\) \}'
        $content | Should -Match '\{ key = "l", mods = "LEADER", action = focus_adjacent_window\("right"\) \}'
        $content | Should -Match '\{ key = "h", mods = "ALT\|SHIFT", action = focus_adjacent_window\("left"\) \}'
        $content | Should -Match '\{ key = "l", mods = "ALT\|SHIFT", action = focus_adjacent_window\("right"\) \}'
        $content | Should -Match '\{ key = "Backspace", mods = "LEADER", action = act\.SendKey\(\{ key = "Backspace" \}\) \}'
    }

    It 'Warp keybindings are no longer managed' {
        Test-Path -LiteralPath (Join-Path $script:chezmoiRoot "terminals/warp/keybindings.yaml") | Should -BeFalse
    }

    It 'VS Code と Cursor は Alt focus, Alt+Shift move に揃えること' {
        foreach ($path in @(
                "chezmoi/editors/vscode/keybindings.json",
                "chezmoi/editors/cursor/keybindings.json"
            )) {
            $bindings = Get-JsonContent $path

            Assert-KeyCommand $bindings "alt+h" "workbench.action.focusLeftGroup"
            Assert-KeyCommand $bindings "alt+j" "workbench.action.focusBelowGroup"
            Assert-KeyCommand $bindings "alt+k" "workbench.action.focusAboveGroup"
            Assert-KeyCommand $bindings "alt+l" "workbench.action.focusRightGroup"

            Assert-KeyCommand $bindings "alt+shift+h" "workbench.action.moveActiveEditorGroupLeft"
            Assert-KeyCommand $bindings "alt+shift+j" "workbench.action.moveActiveEditorGroupDown"
            Assert-KeyCommand $bindings "alt+shift+k" "workbench.action.moveActiveEditorGroupUp"
            Assert-KeyCommand $bindings "alt+shift+l" "workbench.action.moveActiveEditorGroupRight"
        }
    }

    It 'Zed は Alt focus に揃えること' {
        $bindings = Get-ZedWorkspaceBinding

        $bindings.PSObject.Properties["alt-h"].Value[0] | Should -Be "workspace::ActivatePaneInDirection"
        $bindings.PSObject.Properties["alt-h"].Value[1] | Should -Be "Left"
        $bindings.PSObject.Properties["alt-j"].Value[0] | Should -Be "workspace::ActivatePaneInDirection"
        $bindings.PSObject.Properties["alt-j"].Value[1] | Should -Be "Down"
        $bindings.PSObject.Properties["alt-k"].Value[0] | Should -Be "workspace::ActivatePaneInDirection"
        $bindings.PSObject.Properties["alt-k"].Value[1] | Should -Be "Up"
        $bindings.PSObject.Properties["alt-l"].Value[0] | Should -Be "workspace::ActivatePaneInDirection"
        $bindings.PSObject.Properties["alt-l"].Value[1] | Should -Be "Right"
    }

    It 'Unix/Linux/WSL の tmux と Neovim は Ctrl+H/J/K/L focus を維持すること' {
        $tmux = Get-Content -LiteralPath (Join-Path $script:chezmoiRoot "dot_tmux.conf") -Raw
        $nvim = Get-Content -LiteralPath (Join-Path $script:chezmoiRoot "dot_config/nvim/lua/config/keymaps.lua") -Raw

        foreach ($key in @("h", "j", "k", "l")) {
            $tmux | Should -Match "bind-key -n C-$key"
            $nvim | Should -Match "map\(`"n`", `"<C-$key>`""
            $nvim | Should -Match "map\(`"t`", `"<C-$key>`""
        }
    }
}
