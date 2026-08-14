BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
    $script:unixConfig = Join-Path $script:repoRoot 'chezmoi/dot_config/herdr/config.toml'
    $script:windowsConfig = Join-Path $script:repoRoot 'chezmoi/AppData/Roaming/herdr/config.toml'
}

Describe 'Herdr configuration' {
    It 'manages the official Unix and Windows source paths' {
        Test-Path -LiteralPath $script:unixConfig -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $script:windowsConfig -PathType Leaf | Should -BeTrue
    }

    It 'keeps the portable configurations identical' {
        Test-Path -LiteralPath $script:unixConfig -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $script:windowsConfig -PathType Leaf | Should -BeTrue
        $unixContent = Get-Content -LiteralPath $script:unixConfig -Raw
        $windowsContent = Get-Content -LiteralPath $script:windowsConfig -Raw
        $windowsContent | Should -Be $unixContent
    }

    It 'disables onboarding without forcing a platform-invalid channel' {
        Test-Path -LiteralPath $script:unixConfig -PathType Leaf | Should -BeTrue
        $content = Get-Content -LiteralPath $script:unixConfig -Raw
        $content | Should -Match '(?m)^onboarding\s*=\s*false\s*$'
        $content | Should -Match '(?m)^shell_mode\s*=\s*"auto"\s*$'
        $content | Should -Match '(?m)^new_cwd\s*=\s*"follow"\s*$'
        $content | Should -Not -Match '(?m)^channel\s*=\s*"stable"\s*$'
    }

    It 'should define the unified native key contract' {
        $content = Get-Content -LiteralPath $script:unixConfig -Raw
        $expected = [ordered]@{
            prefix                  = 'ctrl+space'
            workspace_picker        = 'prefix+w'
            new_workspace           = 'prefix+a'
            navigate_workspace_down = 'j'
            navigate_workspace_up   = 'k'
            new_tab                 = 'prefix+n'
            close_tab               = 'prefix+q'
            next_tab                = 'prefix+tab'
            previous_tab            = 'prefix+shift+tab'
            focus_pane_left         = 'prefix+h'
            focus_pane_down         = 'prefix+j'
            focus_pane_up           = 'prefix+k'
            focus_pane_right        = 'prefix+l'
            split_vertical          = 'prefix+v'
            split_horizontal        = 'prefix+minus'
            close_pane              = 'prefix+x'
            goto                    = 'prefix+g'
            detach                  = 'prefix+d'
        }

        foreach ($entry in $expected.GetEnumerator()) {
            $content | Should -Match "(?m)^$($entry.Key)\s*=\s*\`"$([regex]::Escape($entry.Value))\`"\s*$"
        }
    }
}
