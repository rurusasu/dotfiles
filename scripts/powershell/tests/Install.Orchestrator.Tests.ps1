#Requires -Module Pester

BeforeAll {
    $script:target = Join-Path (Split-Path -Parent $PSScriptRoot) "install.ps1"
}

Describe 'install.ps1 (orchestrator)' {
    It 'should exist at scripts/powershell/install.ps1' {
        Test-Path -LiteralPath $script:target | Should -BeTrue
    }

    It 'should parse without syntax errors' {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($script:target, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
    }

    It 'should reference user/admin phase scripts' {
        $content = Get-Content -LiteralPath $script:target -Raw
        $content | Should -Match 'install\.user\.ps1'
        $content | Should -Match 'install\.admin\.ps1'
    }

    It 'should elevate admin phase with RunAs' {
        $content = Get-Content -LiteralPath $script:target -Raw
        $content | Should -Match '-Verb RunAs'
    }

    It 'should support NoPause switch for non-interactive runs' {
        $content = Get-Content -LiteralPath $script:target -Raw
        $content | Should -Match '\[switch\]\$NoPause'
    }
}
