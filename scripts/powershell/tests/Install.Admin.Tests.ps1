#Requires -Module Pester

BeforeAll {
    $script:target = Join-Path (Split-Path -Parent $PSScriptRoot) "install.admin.ps1"
}

Describe 'install.admin.ps1' {
    It 'should exist at scripts/powershell/install.admin.ps1' {
        Test-Path -LiteralPath $script:target | Should -BeTrue
    }

    It 'should parse without syntax errors' {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($script:target, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
    }

    It 'should return boolean in CheckOnly mode' {
        $result = & $script:target -CheckOnly
        $result | Should -BeOfType [bool]
    }

    It 'should return boolean in non-admin CheckOnly mode without waiting indefinitely on WSL checks' {
        $oldTimeout = $env:DOTFILES_WSL_CHECK_TIMEOUT_SECONDS
        $env:DOTFILES_WSL_CHECK_TIMEOUT_SECONDS = "1"
        try {
            $elapsed = Measure-Command {
                $result = & $script:target -CheckOnly -AdminOnly:$false
                $result | Should -BeOfType [bool]
            }
            $elapsed.TotalSeconds | Should -BeLessThan 30
        }
        finally {
            $env:DOTFILES_WSL_CHECK_TIMEOUT_SECONDS = $oldTimeout
        }
    }

    It 'should filter handlers by Phase 2' {
        $content = Get-Content -LiteralPath $script:target -Raw
        $content | Should -Match '\$_\.Phase -eq 2'
    }

    It 'should print preflight handler names before Phase 2 apply checks' {
        $content = Get-Content -LiteralPath $script:target -Raw
        $content | Should -Match '適用可否を確認しています'
        $content | Should -Match '\$\(\$handler\.Name\)'
    }
}
