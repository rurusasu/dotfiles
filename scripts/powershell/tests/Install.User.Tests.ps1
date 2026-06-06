#Requires -Module Pester

BeforeAll {
    $script:target = Join-Path (Split-Path -Parent $PSScriptRoot) "install.user.ps1"
}

Describe 'install.user.ps1' {
    It 'should exist at scripts/powershell/install.user.ps1' {
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

    It 'should filter handlers by Phase 1' {
        $content = Get-Content -LiteralPath $script:target -Raw
        $content | Should -Match '\$_\.Phase -eq 1'
    }

    It 'should repair Windows environment variables before computing default paths' {
        $content = Get-Content -LiteralPath $script:target -Raw
        $content | Should -Match 'WindowsEnvironment\.ps1'
        $content | Should -Match 'Repair-WindowsSetupEnvironment'
        $content | Should -Match '\$PSBoundParameters\.ContainsKey\("InstallDir"\)'
    }
}
