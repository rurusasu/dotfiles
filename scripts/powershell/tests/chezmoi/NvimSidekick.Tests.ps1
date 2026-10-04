#Requires -Module Pester

BeforeAll {
    $script:repoRoot = Join-Path $PSScriptRoot "../../../.."
    $script:pluginsPath = Join-Path $script:repoRoot "nix/modules/nvim/plugins.nix"
    $script:pluginsContent = Get-Content -LiteralPath $script:pluginsPath -Raw
    $script:snacks = Get-Content -LiteralPath (Join-Path $script:repoRoot "nix/modules/nvim/lua/plugins/snacks.lua") -Raw
    $script:sidekick = Get-Content -LiteralPath (Join-Path $script:repoRoot "nix/modules/nvim/lua/plugins/sidekick.lua") -Raw
}

Describe 'Neovim Sidekick and Snacks plugin boundaries' {
    It 'should configure Snacks through Home Manager' {
        Test-Path -LiteralPath $script:pluginsPath -PathType Leaf | Should -BeTrue
        $snacks = $script:snacks
        $snacks | Should -Match 'require\("snacks"\)\.setup'
        $snacks | Should -Match '"<leader>ff"'
        $snacks | Should -Match '\["<a-a>"\]'
        $snacks | Should -Match 'sidekick\.cli\.picker\.snacks'
    }

    It 'should configure Sidekick through Home Manager' {
        $sidekick = $script:sidekick
        $sidekick | Should -Match 'require\("sidekick"\)\.setup'
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
        $sidekick = $script:sidekick
        $sidekick | Should -Not -Match 'WinNew'
        $sidekick | Should -Not -Match 'SidekickForceRight'
        $sidekick | Should -Not -Match 'wincmd L'
        $sidekick | Should -Not -Match 'nvim_set_current_win'
    }

    It 'should register Snacks and Sidekick exactly once' {
        [regex]::Matches($script:pluginsContent, 'plugin = pkgs\.vimPlugins\.snacks-nvim;').Count | Should -Be 1
        [regex]::Matches($script:pluginsContent, 'plugin = pkgs\.vimPlugins\.sidekick-nvim;').Count | Should -Be 1
    }
}
