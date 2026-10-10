#Requires -Module Pester

BeforeAll {
    $PSDefaultParameterValues['Get-Content:Encoding'] = 'UTF8'
    $script:repoRoot = Resolve-Path (Join-Path $PSScriptRoot "../../../..")
    $script:chezmoiRoot = Join-Path $script:repoRoot "chezmoi"
    $script:keybindingsDocsPath = if ($env:DOTFILES_KEYBINDINGS_DOCS_PATH) {
        $env:DOTFILES_KEYBINDINGS_DOCS_PATH
    }
    else {
        Join-Path $script:repoRoot "docs/chezmoi/keybindings.md"
    }

    function Invoke-ChezmoiTemplateForTest {
        param([Parameter(Mandatory)][string]$Template, [Parameter(Mandatory)][string]$OverrideData)

        $command = Get-Command chezmoi -ErrorAction Stop
        $arguments = @('--source', $script:chezmoiRoot, "--override-data=$OverrideData", 'execute-template') | ForEach-Object {
            $value = [string]$_
            '"' + (($value -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
        }
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $command.Source
        $startInfo.Arguments = $arguments -join ' '
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $startInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        try {
            if (-not $process.Start()) { throw 'Failed to start chezmoi.' }
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            $inputBytes = ([System.Text.UTF8Encoding]::new($false)).GetBytes($Template)
            $process.StandardInput.BaseStream.Write($inputBytes, 0, $inputBytes.Length)
            $process.StandardInput.Close()
            $process.WaitForExit()
            if ($process.ExitCode -ne 0) { throw "chezmoi execute-template failed ($($process.ExitCode)): $($stderr.GetAwaiter().GetResult())" }
            return $stdout.GetAwaiter().GetResult() -split "`r?`n"
        }
        finally { $process.Dispose() }
    }

    function Get-JsonContent {
        param([string]$Path)
        $fullPath = Join-Path $script:repoRoot $Path
        $raw = Get-Content -Encoding UTF8 -LiteralPath $fullPath -Raw
        if ($raw -notmatch '\{\{') {
            return $raw | ConvertFrom-Json
        }

        $rendered = Invoke-ChezmoiTemplateForTest -Template $raw -OverrideData '{"chezmoi":{"os":"windows"}}'

        ($rendered -join [Environment]::NewLine) | ConvertFrom-Json
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

}

Describe '標準キーバインド方針' {
    It 'docs は editor と Unix/Vim 系の標準レイヤーを明示すること' {
        $docs = Get-Content -Encoding UTF8 -LiteralPath $script:keybindingsDocsPath -Raw

        $docs | Should -Match 'Ctrl\+H/J/K/L' -Because "Unix/Vim focus should keep the standard Ctrl+H/J/K/L layer"
    }

    It 'docs は共通 terminal window-manager metadata を明示すること' {
        $docs = Get-Content -Encoding UTF8 -LiteralPath $script:keybindingsDocsPath -Raw
        $expectations = [ordered]@{
            'Ctrl\+Space Ctrl\+Space'              = 'nested prefix should be documented'
        }

        foreach ($expectation in $expectations.GetEnumerator()) {
            $docs | Should -Match $expectation.Key -Because $expectation.Value
        }
    }

    It 'docs は共通 terminal window-manager suffix table の全行を exactly once で定義すること' {
        $docs = Get-Content -Encoding UTF8 -LiteralPath $script:keybindingsDocsPath -Raw
        $expectedRows = @(
            @{ Target = 'Workspace'; Suffix = '`w`'; Operation = 'picker を開く' },
            @{ Target = 'Workspace'; Suffix = '`a`'; Operation = '新規作成' },
            @{ Target = 'Workspace'; Suffix = '`j` / `k`'; Operation = 'picker 内で次 / 前' },
            @{ Target = 'Tab'; Suffix = '`n`'; Operation = '新規作成' },
            @{ Target = 'Tab'; Suffix = '`q`'; Operation = '閉じる' },
            @{ Target = 'Tab'; Suffix = '`Tab` / `Shift+Tab`'; Operation = '次 / 前' },
            @{ Target = 'Pane'; Suffix = '`h` / `j` / `k` / `l`'; Operation = '左 / 下 / 上 / 右へ移動' },
            @{ Target = 'Pane'; Suffix = '`v` / `-`'; Operation = '左右 / 上下分割' },
            @{ Target = 'Pane'; Suffix = '`x`'; Operation = '閉じる' },
            @{ Target = 'Session'; Suffix = '`g`'; Operation = 'navigator を開く' },
            @{ Target = 'Session'; Suffix = '`d`'; Operation = 'detach' }
        )

        foreach ($expected in $expectedRows) {
            $cells = @($expected.Target, $expected.Suffix, $expected.Operation) |
                ForEach-Object { [regex]::Escape($_) }
            $rowPattern = '(?m)^\|[ \t]*' + ($cells -join '[ \t]*\|[ \t]*') + '[ \t]*\|[ \t]*$'

            [regex]::Matches($docs, $rowPattern).Count |
                Should -Be 1 -Because "$($expected.Target) $($expected.Suffix) should have one exact common-contract row"
        }
    }

    It 'docs は全 target の全 capability cell を定義すること' {
        $docs = Get-Content -Encoding UTF8 -LiteralPath $script:keybindingsDocsPath -Raw
        $expectedTargets = @(
            @{
                Target       = 'WezTerm'
                Capabilities = [ordered]@{ Workspace = '対応'; Tab = '対応'; Pane = '対応'; Session = '対応' }
            },
            @{
                Target       = 'Herdr'
                Capabilities = [ordered]@{ Workspace = '対応'; Tab = '対応'; Pane = '対応'; Session = '対応' }
            }
        )

        foreach ($expected in $expectedTargets) {
            $target = [regex]::Escape($expected.Target)
            $rowPattern = "(?m)^\|[ \t]*$target[ \t]*\|[ \t]*(?<Workspace>[^|\r\n]+?)[ \t]*\|[ \t]*(?<Tab>[^|\r\n]+?)[ \t]*\|[ \t]*(?<Pane>[^|\r\n]+?)[ \t]*\|[ \t]*(?<Session>[^|\r\n]+?)[ \t]*\|[ \t]*$"
            $rows = [regex]::Matches($docs, $rowPattern)
            $rows.Count | Should -Be 1 -Because "$($expected.Target) should have one capability row"

            foreach ($capability in $expected.Capabilities.GetEnumerator()) {
                $rows[0].Groups[$capability.Key].Value.Trim() |
                    Should -Be $capability.Value -Because "$($expected.Target) $($capability.Key) capability should remain explicit"
            }
        }
    }

    It 'docs と source は代表的な旧 terminal window-manager bindings を再導入しないこと' {
        $docs = Get-Content -Encoding UTF8 -LiteralPath $script:keybindingsDocsPath -Raw
        $legacyBindings = @(
            @{
                Name          = 'WezTerm Command split'
                Path          = 'chezmoi/terminals/wezterm/wezterm.lua'
                SourcePattern = 'key = "d", mods = "SUPER(?:\|SHIFT)?", action = act\.Split'
                DocsPattern   = 'Command\+(?:Shift\+)?D.*(?:分割|split)'
            },
            @{
                Name          = 'WezTerm legacy leader tab table'
                Path          = 'chezmoi/terminals/wezterm/wezterm.lua'
                SourcePattern = 'key = "t", mods = "LEADER", action = act\.SpawnTab|mods = "LEADER", action = act\.ActivateTab\([0-8]\)'
                DocsPattern   = 'Leader.*`t/x/1-9`.*タブ操作'
            }
        )

        foreach ($legacy in $legacyBindings) {
            $source = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $script:repoRoot $legacy.Path) -Raw
            $source | Should -Not -Match $legacy.SourcePattern -Because "$($legacy.Name) must remain absent from source"
            $docs | Should -Not -Match $legacy.DocsPattern -Because "$($legacy.Name) must remain absent from docs"
        }
    }

    It 'should preserve native terminal shortcuts and application input bindings' {
        $settings = Get-JsonContent "chezmoi/terminals/windows-terminal/settings.json"
        foreach ($nativeKey in @('ctrl+shift+t', 'ctrl+tab', 'ctrl+shift+tab', 'ctrl+shift+w', 'alt+left', 'alt+right', 'alt+shift+plus', 'alt+shift+minus')) {
            @($settings.keybindings | Where-Object keys -EQ $nativeKey).Count | Should -Be 0 -Because 'native shortcuts must inherit Windows Terminal defaults'
        }
        @($settings.keybindings | Where-Object keys -Match '^f(?:1[3-9]|2[0-3])$').Count | Should -Be 0

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
        $defaultProfile.elevate | Should -BeTrue -Because 'the existing profile elevation policy is independent of keyboard adapters'
    }
    It 'WezTerm は共通 terminal window-manager 契約と nested prefix を提供すること' {
        $content = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $script:chezmoiRoot "terminals/wezterm/wezterm.lua") -Raw

        $content | Should -Match 'key = "Space", mods = "CTRL", timeout_milliseconds = 1000'
        $content | Should -Match 'key = "Space", mods = "LEADER\|CTRL", action = act\.SendKey\(\{ key = "Space", mods = "CTRL" \}\)'
        $content | Should -Match 'key = "w", mods = "LEADER", action = act\.ShowLauncherArgs\(\{ flags = "WORKSPACES" \}\)'
        $content | Should -Not -Match 'key = "w", mods = "LEADER", action = act\.ShowLauncherArgs\(\{ flags = "FUZZY\|WORKSPACES" \}\)'
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


    It 'should preserve native Neovim Ctrl+H/J/K/L focus' {
        $nvim = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $script:repoRoot "nix/modules/editors/nvim/lua/config/keymaps.lua") -Raw

        foreach ($key in @("h", "j", "k", "l")) {
            $nvim | Should -Match "map\(`"n`", `"<C-$key>`""
            $nvim | Should -Match "map\(`"t`", `"<C-$key>`""
        }
    }
}
