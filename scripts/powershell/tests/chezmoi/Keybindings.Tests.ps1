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

        $docs | Should -Match 'Alt\+H/J/K/L' -Because "GUI pane/window focus should use Alt+H/J/K/L"
        $docs | Should -Match 'Alt\+Shift\+H/J/K/L' -Because "GUI pane/window move should add Shift"
        $docs | Should -Match 'Ctrl\+Alt\+H/J/K/L' -Because "GUI pane/window resize should use Ctrl+Alt+H/J/K/L"
        $docs | Should -Match 'Ctrl\+H/J/K/L' -Because "Unix/Vim/tmux focus should keep the standard Ctrl+H/J/K/L layer"
    }

    It 'Windows Terminal は Alt focus, Alt+Shift swap, Ctrl+Alt resize に揃えること' {
        $settings = Get-JsonContent "chezmoi/terminals/windows-terminal/settings.json"

        Assert-WindowsTerminalDirectionalAction $settings "alt+h" "moveFocus" "left"
        Assert-WindowsTerminalDirectionalAction $settings "alt+j" "moveFocus" "down"
        Assert-WindowsTerminalDirectionalAction $settings "alt+k" "moveFocus" "up"
        Assert-WindowsTerminalDirectionalAction $settings "alt+l" "moveFocus" "right"

        Assert-WindowsTerminalDirectionalAction $settings "alt+shift+h" "swapPane" "left"
        Assert-WindowsTerminalDirectionalAction $settings "alt+shift+j" "swapPane" "down"
        Assert-WindowsTerminalDirectionalAction $settings "alt+shift+k" "swapPane" "up"
        Assert-WindowsTerminalDirectionalAction $settings "alt+shift+l" "swapPane" "right"

        Assert-WindowsTerminalDirectionalAction $settings "ctrl+alt+h" "resizePane" "left"
        Assert-WindowsTerminalDirectionalAction $settings "ctrl+alt+j" "resizePane" "down"
        Assert-WindowsTerminalDirectionalAction $settings "ctrl+alt+k" "resizePane" "up"
        Assert-WindowsTerminalDirectionalAction $settings "ctrl+alt+l" "resizePane" "right"
    }

    It 'WezTerm は Alt focus と Ctrl+Alt resize に揃えること' {
        $content = Get-Content -LiteralPath (Join-Path $script:chezmoiRoot "terminals/wezterm/wezterm.lua") -Raw

        $content | Should -Match '\{ key = "h", mods = "ALT", action = act\.ActivatePaneDirection\("Left"\) \}'
        $content | Should -Match '\{ key = "j", mods = "ALT", action = act\.ActivatePaneDirection\("Down"\) \}'
        $content | Should -Match '\{ key = "k", mods = "ALT", action = act\.ActivatePaneDirection\("Up"\) \}'
        $content | Should -Match '\{ key = "l", mods = "ALT", action = act\.ActivatePaneDirection\("Right"\) \}'

        $content | Should -Match '\{ key = "h", mods = "CTRL\|ALT", action = act\.AdjustPaneSize\(\{ "Left", 5 \}\) \}'
        $content | Should -Match '\{ key = "j", mods = "CTRL\|ALT", action = act\.AdjustPaneSize\(\{ "Down", 5 \}\) \}'
        $content | Should -Match '\{ key = "k", mods = "CTRL\|ALT", action = act\.AdjustPaneSize\(\{ "Up", 5 \}\) \}'
        $content | Should -Match '\{ key = "l", mods = "CTRL\|ALT", action = act\.AdjustPaneSize\(\{ "Right", 5 \}\) \}'
    }

    It 'Warp は Alt focus と Ctrl+Alt resize に揃えること' {
        $content = Get-Content -LiteralPath (Join-Path $script:chezmoiRoot "terminals/warp/keybindings.yaml") -Raw

        $content | Should -Match '(?m)^pane_group:navigate_left:\s*alt-h$'
        $content | Should -Match '(?m)^pane_group:navigate_down:\s*alt-j$'
        $content | Should -Match '(?m)^pane_group:navigate_up:\s*alt-k$'
        $content | Should -Match '(?m)^pane_group:navigate_right:\s*alt-l$'

        $content | Should -Match '(?m)^pane_group:resize_left:\s*ctrl-alt-h$'
        $content | Should -Match '(?m)^pane_group:resize_down:\s*ctrl-alt-j$'
        $content | Should -Match '(?m)^pane_group:resize_up:\s*ctrl-alt-k$'
        $content | Should -Match '(?m)^pane_group:resize_right:\s*ctrl-alt-l$'
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
