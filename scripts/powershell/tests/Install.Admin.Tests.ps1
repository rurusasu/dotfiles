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

    It 'should filter handlers by Phase 2' {
        $content = Get-Content -LiteralPath $script:target -Raw
        $content | Should -Match '\$_\.Phase -eq 2'
    }
}
