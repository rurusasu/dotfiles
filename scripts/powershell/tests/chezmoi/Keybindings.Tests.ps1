#Requires -Module Pester

BeforeAll {
    $script:repoRoot = Resolve-Path (Join-Path $PSScriptRoot "../../../..")
    $script:chezmoiRoot = Join-Path $script:repoRoot "chezmoi"

    function Get-JsonContent {
        param([string]$Path)
        Get-Content -LiteralPath (Join-Path $script:repoRoot $Path) -Raw | ConvertFrom-Json
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
        $docs | Should -Match 'Ctrl\+Command\+矢印' -Because "macOS WezTerm resize should use a repeatable modifier chord"
        $docs | Should -Match 'Leader.*pane' -Because "macOS WezTerm leader should control panes"
        $docs | Should -Match 'Alt\+H/J/K/L' -Because "other GUI editors should keep Alt focus"
        $docs | Should -Match 'Ctrl\+H/J/K/L' -Because "Unix/Vim/tmux focus should keep the standard Ctrl+H/J/K/L layer"
    }

    It 'should expose only F13-F23 for Windows Terminal window-manager actions' {
        $settings = Get-JsonContent "chezmoi/terminals/windows-terminal/settings.json"

        $transport = [ordered]@{
            f13 = 'User.newTab'
            f14 = 'User.closeTab'
            f15 = 'User.nextTab'
            f16 = 'User.prevTab'
            f17 = 'User.moveFocus.left'
            f18 = 'User.moveFocus.down'
            f19 = 'User.moveFocus.up'
            f20 = 'User.moveFocus.right'
            f21 = 'User.splitPane.horizontal'
            f22 = 'User.splitPane.vertical'
            f23 = 'User.closePane'
        }
        foreach ($entry in $transport.GetEnumerator()) {
            $bindings = @($settings.keybindings | Where-Object keys -EQ $entry.Key)
            $bindings.Count | Should -Be 1 -Because "$($entry.Key) should have exactly one transport binding"
            $bindings[0].id | Should -Be $entry.Value
            $actionBindings = @($settings.keybindings | Where-Object id -EQ $entry.Value)
            $actionBindings.Count | Should -Be 1 -Because "$($entry.Value) should not retain a direct legacy binding"
            $actionBindings[0].keys | Should -Be $entry.Key
        }

        $legacyKeys = @(
            'ctrl+tab', 'ctrl+shift+tab', 'ctrl+alt+t', 'ctrl+shift+w',
            'alt+left', 'alt+down', 'alt+up', 'alt+right',
            'alt+shift+plus', 'alt+shift+minus',
            'alt+shift+h', 'alt+shift+j', 'alt+shift+k', 'alt+shift+l',
            'alt+shift+left', 'alt+shift+down', 'alt+shift+up', 'alt+shift+right'
        )
        foreach ($legacyKey in $legacyKeys) {
            $unbindings = @($settings.keybindings | Where-Object keys -EQ $legacyKey)
            $unbindings.Count | Should -Be 1 -Because "$legacyKey must explicitly override inherited Windows Terminal defaults"
            $unbindings[0].PSObject.Properties.Name | Should -Contain 'id'
            $unbindings[0].id | Should -BeNullOrEmpty -Because "$legacyKey must be effectively unbound"
        }

        $preserved = [ordered]@{
            'ctrl+c'           = 'User.copy'
            'ctrl+v'           = 'User.paste'
            'ctrl+shift+f'     = 'User.find'
            'shift+enter'      = 'User.sendInput.ShiftEnter'
            'ctrl+enter'       = 'User.sendInput.CtrlEnter'
            'ctrl+alt+w'       = 'User.togglePaneZoom'
            'f11'              = 'User.toggleFullscreen'
            'ctrl+shift+0'     = 'User.resetFontSize'
            'ctrl+shift+plus'  = 'User.increaseFontSize'
            'ctrl+shift+minus' = 'User.decreaseFontSize'
        }
        foreach ($entry in $preserved.GetEnumerator()) {
            @($settings.keybindings | Where-Object keys -EQ $entry.Key).id | Should -Be $entry.Value
        }

        $defaultProfile = @($settings.profiles.list | Where-Object guid -EQ $settings.defaultProfile) | Select-Object -First 1
        $defaultProfile.elevate | Should -BeTrue -Because 'UIAccess transport must preserve the managed profile elevation policy'
    }

    It 'should implement the Windows Terminal AutoHotkey prefix state and mapping contract' {
        $path = Join-Path $script:chezmoiRoot 'terminals/windows-terminal/terminal-keybindings.ahk'
        Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue
        $ahk = Get-Content -LiteralPath $path -Raw

        $ahk | Should -Match '#Requires AutoHotkey v2\.0'
        $ahk | Should -Match '#HotIf WinActive\("ahk_exe WindowsTerminal\.exe"\).*IsExactTerminalPrefix\(\)'
        $ahk | Should -Match '\$\^Space::StartTerminalPrefix\(\)'
        $ahk | Should -Match 'InputHook\("T1"\)'
        $ahk | Should -Match 'KeyOpt\("\{All\}", "NS"\)'
        $ahk | Should -Match 'KeyOpt\("\{LCtrl\}\{RCtrl\}\{LAlt\}\{RAlt\}\{LShift\}\{RShift\}\{LWin\}\{RWin\}", "-S"\)'
        $ahk | Should -Match 'A_Args\[1\] = "--check"'
        $ahk | Should -Match 'A_Args\[1\] = "--self-test"'
        $ahk | Should -Match 'RunTerminalSelfTests\(\)'
        $ahk | Should -Match '(?s)IsExactTerminalPrefix\(\).*?GetKeyState\("Shift", "P"\).*?GetKeyState\("Alt", "P"\).*?GetKeyState\("LWin", "P"\).*?GetKeyState\("RWin", "P"\)'
        $ahk | Should -Match '(?s)IsTerminalModifierKey\(key\).*?return'
        $ahk | Should -Match 'ForwardNestedTerminalPrefix\(TerminalInputHook, SendTerminalOutput\)'
        $ahk | Should -Match 'ProcessTerminalSuffix\('
        $ahk | Should -Match 'RunTerminalResolverSelfTests\(\)'
        $ahk | Should -Match 'RunTerminalStateSelfTests\(\)'
        $ahk | Should -Not -Match '(?i)Stop-Process|taskkill|ProcessClose'

        if ($IsWindows) {
            $autoHotkey = "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe"
            Test-Path -LiteralPath $autoHotkey -PathType Leaf |
                Should -BeTrue -Because 'Windows CI must machine-install AutoHotkey v2'

            & $autoHotkey '/ErrorStdOut' $path '--check'
            $LASTEXITCODE | Should -Be 0

            $selfTestOutput = & $autoHotkey '/ErrorStdOut' $path '--self-test' 2>&1
            $LASTEXITCODE | Should -Be 0
            $selfTestOutput -join [Environment]::NewLine | Should -Match 'Terminal self-tests: PASS'
        }
    }

    It 'should provision AutoHotkey v2 in every Windows CI job that runs chezmoi Pester' {
        $ciJobs = @(
            @{ Workflow = '.github/workflows/ci-chezmoi.yml'; Job = 'lint'; PesterStep = '- name: Install Pester' },
            @{ Workflow = '.github/workflows/ci-chezmoi.yml'; Job = 'test'; PesterStep = '- name: Install Pester' },
            @{ Workflow = '.github/workflows/ci-powershell.yml'; Job = 'test'; PesterStep = '- name: Install PowerShell modules' },
            @{ Workflow = '.github/workflows/ci-bootstrap-e2e-hosted.yml'; Job = 'windows'; PesterStep = '- name: Install pinned Pester' }
        )
        foreach ($case in $ciJobs) {
            $workflow = Get-Content -LiteralPath (Join-Path $script:repoRoot $case.Workflow) -Raw
            $job = [regex]::Match(
                $workflow,
                "(?ms)^  $($case.Job)`:\s*.*?(?=^  [a-zA-Z0-9_-]+`:\s*$|\z)"
            ).Value
            $job | Should -Not -BeNullOrEmpty
            $job | Should -Match 'winget install --id AutoHotkey\.AutoHotkey --exact --scope machine'
            $job | Should -Match 'AutoHotkey\\v2\\AutoHotkey64\.exe'
            $job | Should -Match 'AutoHotkey\\v2\\AutoHotkey64_UIA\.exe'
            $job | Should -Match "'/ErrorStdOut'.*'--check'"
            $job | Should -Match "'/ErrorStdOut'.*'--self-test'"
            $job.IndexOf('winget install --id AutoHotkey.AutoHotkey') |
                Should -BeLessThan $job.IndexOf($case.PesterStep) -Because "$($case.Workflow) $($case.Job) must install AutoHotkey before Pester"
        }
    }

    It 'WezTerm は共通 terminal window-manager 契約と nested prefix を提供すること' {
        $content = Get-Content -LiteralPath (Join-Path $script:chezmoiRoot "terminals/wezterm/wezterm.lua") -Raw

        $content | Should -Match 'key = "Space", mods = "CTRL", timeout_milliseconds = 1000'
        $content | Should -Match 'key = "Space", mods = "LEADER", action = act\.SendKey\(\{ key = "Space", mods = "CTRL" \}\)'
        $content | Should -Match 'key = "w", mods = "LEADER", action = act\.ShowLauncherArgs\(\{ flags = "FUZZY\|WORKSPACES" \}\)'
        $content | Should -Match '(?s)key = "a",\s*mods = "LEADER",\s*action = act\.PromptInputLine'
        $content | Should -Match 'key = "n", mods = "LEADER", action = act\.SpawnTab\("CurrentPaneDomain"\)'
        $content | Should -Match 'key = "q", mods = "LEADER", action = act\.CloseCurrentTab'
        $content | Should -Match 'key = "Tab", mods = "LEADER", action = act\.ActivateTabRelative\(1\)'
        $content | Should -Match 'key = "Tab", mods = "LEADER\|SHIFT", action = act\.ActivateTabRelative\(-1\)'
        $content | Should -Match 'key = "h", mods = "LEADER", action = act\.ActivatePaneDirection\("Left"\)'
        $content | Should -Match 'key = "j", mods = "LEADER", action = act\.ActivatePaneDirection\("Down"\)'
        $content | Should -Match 'key = "k", mods = "LEADER", action = act\.ActivatePaneDirection\("Up"\)'
        $content | Should -Match 'key = "l", mods = "LEADER", action = act\.ActivatePaneDirection\("Right"\)'
        $content | Should -Match 'key = "v", mods = "LEADER", action = act\.SplitHorizontal'
        $content | Should -Match 'key = "-", mods = "LEADER", action = act\.SplitVertical'
        $content | Should -Match 'key = "x", mods = "LEADER", action = act\.CloseCurrentPane'
        $content | Should -Match 'flags = "FUZZY\|WORKSPACES\|TABS\|DOMAINS"'
        $content | Should -Match 'key = "d", mods = "LEADER", action = act\.DetachDomain\("CurrentPaneDomain"\)'
        $content | Should -Not -Match 'mods = "LEADER", action = act\.ActivateTab\([0-8]\)'

        $content | Should -Not -Match 'key = "t", mods = "LEADER", action = act\.SpawnTab'
        $content | Should -Not -Match 'key = "x", mods = "LEADER", action = act\.CloseCurrentTab'
        $content | Should -Not -Match 'key = "(?:h|l)", mods = "LEADER", action = focus_adjacent_window'
        $content | Should -Not -Match 'key = "(?:LeftArrow|UpArrow|RightArrow|DownArrow)", mods = "LEADER", action = act\.ActivatePaneDirection'
        $content | Should -Not -Match 'key = "d", mods = "SUPER(?:\|SHIFT)?", action = act\.Split'
        $content | Should -Not -Match 'key = "(?:\+|-)", mods = "ALT\|SHIFT", action = act\.Split'
        $content | Should -Not -Match 'key = "(?:LeftArrow|UpArrow|RightArrow|DownArrow)", mods = "ALT", action = act\.ActivatePaneDirection'

        $content | Should -Match '\{ key = "LeftArrow", mods = "SUPER\|CTRL", action = act\.AdjustPaneSize\(\{ "Left", 1 \}\) \}'
        $content | Should -Match '\{ key = "UpArrow", mods = "SUPER\|CTRL", action = act\.AdjustPaneSize\(\{ "Up", 1 \}\) \}'
        $content | Should -Match '\{ key = "RightArrow", mods = "SUPER\|CTRL", action = act\.AdjustPaneSize\(\{ "Right", 1 \}\) \}'
        $content | Should -Match '\{ key = "DownArrow", mods = "SUPER\|CTRL", action = act\.AdjustPaneSize\(\{ "Down", 1 \}\) \}'
        $content | Should -Not -Match 'mods = "LEADER\|SHIFT", action = act\.AdjustPaneSize'

        $content | Should -Match '\{ key = "LeftArrow", mods = "ALT\|SHIFT", action = act\.AdjustPaneSize\(\{ "Left", 5 \}\) \}'
        $content | Should -Match '\{ key = "UpArrow", mods = "ALT\|SHIFT", action = act\.AdjustPaneSize\(\{ "Up", 5 \}\) \}'
        $content | Should -Match '\{ key = "RightArrow", mods = "ALT\|SHIFT", action = act\.AdjustPaneSize\(\{ "Right", 5 \}\) \}'
        $content | Should -Match '\{ key = "DownArrow", mods = "ALT\|SHIFT", action = act\.AdjustPaneSize\(\{ "Down", 5 \}\) \}'

        $content | Should -Match '\{ key = "h", mods = "SUPER\|ALT", action = focus_adjacent_window\("left"\) \}'
        $content | Should -Match '\{ key = "l", mods = "SUPER\|ALT", action = focus_adjacent_window\("right"\) \}'
        $content | Should -Match '\{ key = "h", mods = "ALT\|SHIFT", action = focus_adjacent_window\("left"\) \}'
        $content | Should -Match '\{ key = "l", mods = "ALT\|SHIFT", action = focus_adjacent_window\("right"\) \}'
        $content | Should -Match '\{ key = "Backspace", mods = "LEADER", action = act\.SendKey\(\{ key = "Backspace" \}\) \}'
    }

    It 'should provide the Terminal.app prefix adapter contract' {
        $path = Join-Path $script:chezmoiRoot 'terminals/hammerspoon/init.lua'

        Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue
        $content = Get-Content -LiteralPath $path -Raw

        $content | Should -Match 'com\.apple\.Terminal'
        $content | Should -Match 'hs\.timer\.doAfter\(1'
        $content | Should -Match 'send\(\{ "cmd" \}, "t"'
        $content | Should -Match 'send\(\{ "cmd" \}, "w"'
        $content | Should -Match 'send\(\{ "ctrl" \}, "tab"'
        $content | Should -Match 'send\(\{ "ctrl", "shift" \}, "tab"'
        $content | Should -Match 'send\(\{ "cmd" \}, "d"'
        $content | Should -Match 'send\(\{ "cmd", "shift" \}, "d"'
        $content | Should -Match 'hs\.eventtap\.keyStroke\(mods, key, 0\)'
        $content | Should -Match 'string\.char\(0x19\)'
        $content | Should -Match 'hasExactModifiers'
        $content | Should -Match 'hs\.eventtap\.event\.newKeyEventSequence\(\{ "ctrl" \}, "space"\)'
        $content | Should -Not -Match 'forwardingPrefix'
        $content | Should -Not -Match 'hs\.timer\.doAfter\(0'
        $content | Should -Match '(?s)frontmostApplication\(\).*?bundleID\(\) ~= terminalBundleId.*?resetPrefix\(\).*?return false'
        $content | Should -Match '(?s)local action = nil.*?hasExactModifiers\(flags, noModifiers\).*?suffixActions\[key\].*?backTabCharacter.*?hasExactModifiers\(flags, shiftOnly\).*?suffixActions\.shift_tab.*?resetPrefix\(\)\s*if\s+action\s+then\s+action\(\)\s+end\s*return true'
        $content | Should -Match 'hs\.accessibilityState\(\)'
        $content | Should -Match '(?s)if hs\.accessibilityState\(\) then\s*terminalPrefixTap:start\(\)\s*else\s*hs\.alert\.show'
        $content | Should -Match 'hs\.autoLaunch\(true\)'
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

        $tmux | Should -Match '(?m)^set -g prefix C-Space$'
        $tmux | Should -Match '(?m)^bind C-Space send-prefix$'
        foreach ($binding in @(
                @{ Key = 'w'; Command = 'choose-tree -s' },
                @{ Key = 'a'; Command = 'command-prompt' },
                @{ Key = 'n'; Command = 'new-window' },
                @{ Key = 'q'; Command = 'kill-window' },
                @{ Key = 'Tab'; Command = 'next-window' },
                @{ Key = 'BTab'; Command = 'previous-window' },
                @{ Key = 'h'; Command = 'select-pane -L' },
                @{ Key = 'j'; Command = 'select-pane -D' },
                @{ Key = 'k'; Command = 'select-pane -U' },
                @{ Key = 'l'; Command = 'select-pane -R' },
                @{ Key = 'v'; Command = 'split-window -h' },
                @{ Key = '-'; Command = 'split-window -v' },
                @{ Key = 'x'; Command = 'kill-pane' },
                @{ Key = 'g'; Command = 'choose-tree -Zw' },
                @{ Key = 'd'; Command = 'detach-client' }
            )) {
            $tmux | Should -Match "(?m)^bind $([regex]::Escape($binding.Key)) $([regex]::Escape($binding.Command))"
        }
        $tmux | Should -Not -Match '(?m)^set -g prefix C-a$'

        foreach ($key in @("h", "j", "k", "l")) {
            $tmux | Should -Match "bind-key -n C-$key"
            $nvim | Should -Match "map\(`"n`", `"<C-$key>`""
            $nvim | Should -Match "map\(`"t`", `"<C-$key>`""
        }
    }
}
