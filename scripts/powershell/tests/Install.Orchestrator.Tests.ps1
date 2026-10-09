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

    It 'should call only GUI user setup and not provision WSL or run CLI acceptance' {
        $content = Get-Content -LiteralPath $script:target -Raw
        $content | Should -Match 'install\.user\.ps1'
        $content | Should -Not -Match 'install\.admin\.ps1|Test-DotfilesEnvironment|Start-Process|NixOS|Invoke-ConsentPrompt'
    }

    It 'should support noninteractive GUI verification and completion' {
        $content = Get-Content -LiteralPath $script:target -Raw
        $content | Should -Match '\[switch\]\$NoPause'
        $content | Should -Match '\[switch\]\$UserPhaseOnly'
        $content | Should -Match '\[switch\]\$WingetVerifyCommandOnly'
        $content | Should -Match 'WingetVerifyCommandOnly'
    }

    It 'should repair the Windows environment before invoking GUI setup' {
        $content = Get-Content -LiteralPath $script:target -Raw
        $content | Should -Match 'WindowsEnvironment\.ps1'
        $content | Should -Match 'Repair-WindowsSetupEnvironment'
    }

    It 'install.cmd should invoke the explicit PowerShell 7 path without changing PATH' {
        $content = Get-Content -LiteralPath $script:cmdTarget -Raw
        $content | Should -Match 'if defined DOTFILES_PS7_DIR'
        $content | Should -Match 'set "PS7_DIR=%DOTFILES_PS7_DIR%"'
        $content | Should -Match 'set "PS7_DIR=%ProgramFiles%\\PowerShell\\7"'
        $content | Should -Match 'if exist "%PS7_DIR%\\pwsh\.exe"'
        $content | Should -Not -Match 'set "PATH=%PS7_DIR%;%PATH%"'
        $content | Should -Match 'set "PS_CMD=%PS7_DIR%\\pwsh\.exe"'
        $content | Should -Match 'for %%I in \(pwsh\.exe\) do if not "%%~\$PATH:I"==""'
        $content | Should -Not -Match 'where\.exe.*pwsh'
        $content | Should -Match '%SystemRoot%\\System32\\WindowsPowerShell\\v1\.0\\powershell\.exe'
        $content | Should -Match 'Falling back to Windows PowerShell'
    }
}
