#Requires -Module Pester

BeforeAll {
    $script:target = Join-Path (Split-Path -Parent $PSScriptRoot) "install.admin.ps1"
    $script:runsOnWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
    $script:windowsPowerShell = if ($script:runsOnWindows) {
        (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
    }
    else {
        $null
    }
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

    It 'should accept AdminOnly when invoked through powershell.exe -File like the elevated admin phase' {
        if (-not $script:windowsPowerShell) {
            Set-ItResult -Skipped -Because "Windows PowerShell is required to verify the elevated -File argument boundary"
            return
        }

        $output = & $script:windowsPowerShell `
            -NoLogo `
            -NoProfile `
            -ExecutionPolicy Bypass `
            -File $script:target `
            -CheckOnly `
            "-AdminOnly:$true" `
            -OptionsJson '{"SkipWslInstall":true,"SkipVhdExpand":true}' 2>&1
        $exitCode = $LASTEXITCODE
        $outputText = ($output | Out-String).Trim()

        $exitCode | Should -Be 0 -Because $outputText
        $outputText | Should -Be "False"
    }

    It 'should filter handlers by Phase 2' {
        $content = Get-Content -LiteralPath $script:target -Raw
        $content | Should -Match '\$_\.Phase -eq 2'
    }

    It 'should repair Windows environment variables before computing default paths' {
        $content = Get-Content -LiteralPath $script:target -Raw
        $content | Should -Match 'WindowsEnvironment\.ps1'
        $content | Should -Match 'Repair-WindowsSetupEnvironment'
        $content | Should -Match '\$PSBoundParameters\.ContainsKey\("InstallDir"\)'
    }

    It 'should print preflight handler names before Phase 2 apply checks' {
        $content = Get-Content -LiteralPath $script:target -Raw
        $content | Should -Match '適用可否を確認しています'
        $content | Should -Match '\$\(\$handler\.Name\)'
    }

    It 'should skip WSL-dependent final processing when WSL is still unavailable' {
        $content = Get-Content -LiteralPath $script:target -Raw
        $content | Should -Match 'Test-WslAvailable'
        $content | Should -Match 'WSL is not available yet'
        $content | Should -Match '(?s)elseif \(-not \(Test-WslAvailable\)\).*else.*Invoke-Wsl --set-default'
    }

    It 'should skip WSL-dependent final processing after WslInstall requires restart' {
        $content = Get-Content -LiteralPath $script:target -Raw
        $content | Should -Match 'wslInstallRequiresRestart'
        $content | Should -Match 'WSL was installed and requires a Windows restart'
        $content | Should -Match '(?s)if \(\$wslInstallRequiresRestart\).*elseif \(-not \(Test-WslAvailable\)\).*else.*Invoke-Wsl --set-default'
    }
}
