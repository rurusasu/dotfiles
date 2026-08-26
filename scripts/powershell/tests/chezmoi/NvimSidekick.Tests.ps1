#Requires -Module Pester

BeforeAll {
    $script:repoRoot = Join-Path $PSScriptRoot "../../../.."
    $script:pluginsDir = Join-Path $script:repoRoot "chezmoi/dot_config/nvim/lua/plugins"
    $script:initPath = Join-Path $script:pluginsDir "init.lua"
    $script:snacksPath = Join-Path $script:pluginsDir "snacks.lua"
    $script:sidekickPath = Join-Path $script:pluginsDir "sidekick.lua"
    $script:initContent = Get-Content -LiteralPath $script:initPath -Raw
}

Describe 'Neovim Sidekick and Snacks plugin boundaries' {
    It 'should keep Snacks in its own plugin spec' {
        Test-Path -LiteralPath $script:snacksPath -PathType Leaf | Should -BeTrue
        $snacks = Get-Content -LiteralPath $script:snacksPath -Raw
        $snacks | Should -Match '"folke/snacks\.nvim"'
        $snacks | Should -Match '"<leader>ff"'
        $snacks | Should -Match '\["<a-a>"\]'
        $snacks | Should -Match 'sidekick\.cli\.picker\.snacks'
    }

    It 'should keep Sidekick in its own plugin spec' {
        Test-Path -LiteralPath $script:sidekickPath -PathType Leaf | Should -BeTrue
        $sidekick = Get-Content -LiteralPath $script:sidekickPath -Raw
        $sidekick | Should -Match '"folke/sidekick\.nvim"'
        $sidekick | Should -Match 'layout = "right"'
        $sidekick | Should -Match '"<C-.>"'
        $sidekick | Should -Not -Match '"<leader>aa"'
        $sidekick | Should -Not -Match '(?i)claude'
        $sidekick | Should -Match '"<leader>af"'
        $sidekick | Should -Match '"<C-S-h>"'
        $sidekick | Should -Match '"<C-S-l>"'
        $sidekick | Should -Match 'enabled = false'
    }

    It 'should not override global window creation or steal picker focus' {
        $sidekick = Get-Content -LiteralPath $script:sidekickPath -Raw
        $sidekick | Should -Not -Match 'WinNew'
        $sidekick | Should -Not -Match 'SidekickForceRight'
        $sidekick | Should -Not -Match 'wincmd L'
        $sidekick | Should -Not -Match 'nvim_set_current_win'
    }

    It 'should remove duplicate Snacks and Sidekick specs from init.lua' {
        $script:initContent | Should -Not -Match '"folke/snacks\.nvim"'
        $script:initContent | Should -Not -Match '"folke/sidekick\.nvim"'
        $script:initContent | Should -Not -Match 'resize_sidekick_cli'
    }
}
