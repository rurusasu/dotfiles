#Requires -Module Pester

BeforeAll {
    $script:repoRoot = Join-Path $PSScriptRoot "../../../.."
    $script:optionsPath = Join-Path $script:repoRoot "nix/modules/nvim/init.lua"
    $script:lspPath = Join-Path $script:repoRoot "nix/modules/nvim/lua/config/lsp.lua"
    $script:nixLspProxyPath = Join-Path $script:repoRoot "chezmoi/dot_local/bin/executable_nix-lsp-wsl-proxy.mjs"
    $script:optionsContent = Get-Content -LiteralPath $script:optionsPath -Raw
    $script:lspContent = Get-Content -LiteralPath $script:lspPath -Raw
    $script:nixLspProxyContent = if (Test-Path -LiteralPath $script:nixLspProxyPath -PathType Leaf) {
        Get-Content -LiteralPath $script:nixLspProxyPath -Raw
    }
    else {
        ""
    }
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

    It 'should include a Windows-to-WSL nixd proxy with URI translation' {
        Test-Path -LiteralPath $script:nixLspProxyPath -PathType Leaf | Should -Be $true
        $script:nixLspProxyContent | Should -Match 'spawn\(\s*"wsl\.exe"'
        $script:nixLspProxyContent | Should -Match '"--distribution"'
        $script:nixLspProxyContent | Should -Match '"--user"'
        $script:nixLspProxyContent | Should -Match '"--exec"'
        $script:nixLspProxyContent | Should -Match '"sh"\s*,\s*"-lc"'
        $script:nixLspProxyContent | Should -Match 'backendRelaySource'
        $script:nixLspProxyContent | Should -Match 'process\.stdin\.pipe'
        $script:nixLspProxyContent | Should -Match 'Content-Length'
        $script:nixLspProxyContent | Should -Match 'windowsUriToWslUri'
        $script:nixLspProxyContent | Should -Match 'wslUriToWindowsUri'
        $script:nixLspProxyContent | Should -Match '/mnt/'
    }

    It 'should pass the nixd proxy self test when node is available' {
        if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because "node is not available"
            return
        }

        $output = & node $script:nixLspProxyPath --self-test

        $LASTEXITCODE | Should -Be 0
        $output | Should -Contain "ok"
    }
}
