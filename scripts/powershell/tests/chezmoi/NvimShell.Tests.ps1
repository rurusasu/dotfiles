#Requires -Module Pester

BeforeAll {
    $script:repoRoot = Join-Path $PSScriptRoot "../../../.."
    $script:optionsPath = Join-Path $script:repoRoot "chezmoi/dot_config/nvim/lua/config/options.lua"
    $script:optionsContent = Get-Content -LiteralPath $script:optionsPath -Raw
}

Describe 'Neovim shell configuration' {
    It 'should use PowerShell for Windows terminal commands' {
        $script:optionsContent | Should -Match 'vim\.fn\.has\("win32"\) == 1'
        $script:optionsContent | Should -Match 'opt\.shell = '
        $script:optionsContent | Should -Match 'pwsh\.exe'
        $script:optionsContent | Should -Match 'powershell\.exe'
        $script:optionsContent | Should -Match 'opt\.shellcmdflag = '
        $script:optionsContent | Should -Match 'opt\.shellquote = ""'
        $script:optionsContent | Should -Match 'opt\.shellxquote = ""'
    }
}
