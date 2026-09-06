#Requires -Module Pester

BeforeAll {
    $script:repoRoot = Join-Path $PSScriptRoot "../../../.."
    $script:optionsPath = Join-Path $script:repoRoot "chezmoi/dot_config/nvim/lua/config/options.lua"
    $script:lspPath = Join-Path $script:repoRoot "chezmoi/dot_config/nvim/lua/config/lsp.lua"
    $script:nixdPath = Join-Path $script:repoRoot "chezmoi/dot_config/nvim/after/lsp/nixd.lua"
    $script:nixLspProxyPath = Join-Path $script:repoRoot "chezmoi/dot_local/bin/executable_nix-lsp-wsl-proxy.mjs"
    $script:optionsContent = Get-Content -LiteralPath $script:optionsPath -Raw
    $script:lspContent = Get-Content -LiteralPath $script:lspPath -Raw
    $script:nixdContent = Get-Content -LiteralPath $script:nixdPath -Raw
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

    It 'should use the WSL nixd proxy for Nix files on Windows' {
        $script:nixdContent | Should -Match 'vim\.fn\.has\("win32"\) == 1'
        $script:nixdContent | Should -Match '\{ "node", vim\.fn\.expand\("~/\.local/bin/nix-lsp-wsl-proxy\.mjs"\) \}'
        $script:nixdContent | Should -Match 'or \{ "nixd" \}'
        $script:lspContent | Should -Match 'vim\.lsp\.enable\(name\)'
        $script:lspContent | Should -Match 'vim\.fn\.executable\("wsl.exe"\) == 1'
        $script:lspContent | Should -Not -Match 'nil_ls'
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
