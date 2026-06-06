#Requires -Module Pester

BeforeAll {
    $script:target = Join-Path (Split-Path -Parent $PSScriptRoot) "install.ps1"
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $script:cmdTarget = Join-Path $script:repoRoot "install.cmd"
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

    It 'should handle canceled admin elevation without throwing' {
        $content = Get-Content -LiteralPath $script:target -Raw
        $content | Should -Match 'catch \[System\.InvalidOperationException\]'
        $content | Should -Match 'Admin phase was canceled'
        $content | Should -Match 'Admin phase skipped'
    }

    It 'should exit with failure when admin phase is skipped' {
        $content = Get-Content -LiteralPath $script:target -Raw
        $content | Should -Match 'Setup Incomplete'
        $content | Should -Match '(?s)Admin phase skipped.*exit 1'
    }

    It 'should support NoPause switch for non-interactive runs' {
        $content = Get-Content -LiteralPath $script:target -Raw
        $content | Should -Match '\[switch\]\$NoPause'
    }

    It 'should support CI user-phase package verification switches' {
        $content = Get-Content -LiteralPath $script:target -Raw
        $content | Should -Match '\[switch\]\$UserPhaseOnly'
        $content | Should -Match '\[switch\]\$WingetVerifyCommandOnly'
        $content | Should -Match 'WingetVerifyCommandOnly'
    }

    It 'should repair Windows environment variables before computing default paths' {
        $content = Get-Content -LiteralPath $script:target -Raw
        $content | Should -Match 'WindowsEnvironment\.ps1'
        $content | Should -Match 'Repair-WindowsSetupEnvironment'
        $content | Should -Match '\$PSBoundParameters\.ContainsKey\("InstallDir"\)'
    }

    It 'install.cmd should prepend the PowerShell 7 MSI directory before resolving pwsh' {
        $content = Get-Content -LiteralPath $script:cmdTarget -Raw
        $content | Should -Match 'set "PS7_DIR=%ProgramFiles%\\PowerShell\\7"'
        $content | Should -Match 'if exist "%PS7_DIR%\\pwsh\.exe"'
        $content | Should -Match 'set "PATH=%PS7_DIR%;%PATH%"'
        $content | Should -Match 'where pwsh'
        $content | Should -Match 'Falling back to Windows PowerShell'
    }
}
