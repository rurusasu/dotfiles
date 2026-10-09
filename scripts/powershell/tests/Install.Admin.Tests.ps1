#Requires -Module Pester

BeforeAll {
    $script:target = Join-Path (Split-Path -Parent $PSScriptRoot) "install.admin.ps1"
    $script:entrypoint = Join-Path (Split-Path -Parent $PSScriptRoot) "install.ps1"
    # Exercise the -File boundary with the same runtime as the current CI matrix leg.
    $script:fileBoundaryShell = (Get-Process -Id $PID).Path
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
                # Fixture the prerequisite already validated by NixRebuild;
                # this test checks the CheckOnly boundary, not a real WSL install.
                $result = & $script:target -CheckOnly -AdminOnly:$false -Options @{ NixRebuildApplied = $true }
                $result | Should -BeOfType [bool]
            }
            $elapsed.TotalSeconds | Should -BeLessThan 30
        }
        finally {
            $env:DOTFILES_WSL_CHECK_TIMEOUT_SECONDS = $oldTimeout
        }
    }

    It 'should accept AdminOnly when invoked through a PowerShell -File boundary like the elevated admin phase' {
        $optionsJson = '{"SkipWslInstall":true,"SkipVhdExpand":true}'
        $optionsBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($optionsJson))
        $output = & $script:fileBoundaryShell `
            -NoLogo `
            -NoProfile `
            -ExecutionPolicy Bypass `
            -File $script:target `
            -CheckOnly `
            "-AdminOnly:$true" `
            -OptionsBase64 $optionsBase64 2>&1
        $exitCode = $LASTEXITCODE
        $outputText = ($output | Out-String).Trim()
        $outputLines = @(
            $output |
                ForEach-Object { [string]$_ } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )

        $exitCode | Should -Be 0 -Because $outputText
        $outputText | Should -Not -Match "Cannot process argument transformation on parameter 'AdminOnly'"
        # GUI setup has no administrator-only package entries. The standalone
        # legacy admin adapter must remain idle with WSL/VHD explicitly skipped.
        $outputLines[-1] | Should -Be "False" -Because $outputText
    }

    It 'should leave the standalone admin adapter outside GUI setup' {
        $content = Get-Content -LiteralPath $script:entrypoint -Raw
        $content | Should -Not -Match 'install\.admin\.ps1|Start-Process|OptionsBase64'
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

    It 'should keep the preflight status text out of normal Phase 2 execution' {
        $content = Get-Content -LiteralPath $script:target -Raw
        $content | Should -Not -Match '適用可否を確認しています'
    }

    It 'should only reserve full handler preflight for CheckOnly mode' {
        $content = Get-Content -LiteralPath $script:target -Raw
        $content | Should -Match '(?s)if \(\$CheckOnly\) \{.*\$handler\.CanApply\(\$context\).*return \(\$applicableCount -gt 0\).*\$results = Invoke-SetupHandler'
    }

    It 'should preload handler files in the admin script scope before instantiating them' {
        $content = Get-Content -LiteralPath $script:target -Raw
        $content | Should -Match '(?s)\$handlerFiles\s*=.*Get-ChildItem.*Handler\.\*\.ps1.*foreach \(\$file in \$handlerFiles\)\s*\{\s*\. \$file\.FullName\s*\}.*Get-SetupHandler\s+-HandlersPath \$handlersPath\s+-SkipLoad'
    }

    It 'should only pause the elevated child when NoPause is not requested' {
        $content = Get-Content -LiteralPath $script:target -Raw
        $content | Should -Match '(?s)\[switch\]\$NoPause.*if \(\$LogFile -and -not \$NoPause\).*Read-Host'
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

    It 'should inspect Docker VHD virtual size when Hyper-V is unavailable' {
        $content = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $script:target) '..\..\windows\expand-docker-vhd.ps1') -Raw
        $content | Should -Match 'Get-DiskpartVhdxVirtualSizeGB'
        $content | Should -Match '(?s)Hyper-V module unavailable.*Get-DiskpartVhdxVirtualSizeGB\s+-Path \$vhdxPath'
    }

    It 'should require an explicit option before expanding Docker Desktop storage' {
        $content = Get-Content -LiteralPath $script:target -Raw
        $content | Should -Match '\$effectiveOptions\["ExpandDockerVhd"\] -eq \$true -and'
    }
}
