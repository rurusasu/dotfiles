Describe 'Windows installer success workflow contract' {
    BeforeAll {
        $workflowPath = Join-Path $PSScriptRoot '../../../../.github/workflows/ci-bootstrap.yml'
        $script:workflowLines = @(Get-Content -LiteralPath $workflowPath -Encoding UTF8)
    }

    It 'passes package-manager success markers into the actual installer success assertion' {
        $start = -1
        for ($index = 0; $index -lt $script:workflowLines.Count; $index++) {
            if ($script:workflowLines[$index].Trim() -eq 'Assert-WindowsInstallerSuccess `') {
                $start = $index
                break
            }
        }

        $start | Should -BeGreaterOrEqual 0
        $callLines = @()
        for ($index = $start; $index -lt $script:workflowLines.Count; $index++) {
            $line = $script:workflowLines[$index]
            $callLines += $line
            if (-not $line.TrimEnd().EndsWith('`')) {
                break
            }
        }

        ($callLines -join "`n") | Should -Match '(?m)^\s*-RequiredOutputMarkers\s+\$requiredPackageManagerMarkers\s*$'
    }

    It 'requires success evidence for every un-gated npm and pnpm manifest package' {
        $workflow = $script:workflowLines -join "`n"
        $workflow | Should -Match '\$npmManifest\s*=\s*Get-Content'
        $workflow | Should -Match '\$pnpmManifest\s*=\s*Get-Content'
        $workflow | Should -Match '\[Npm\] \u2713 \$\(\$package\.name\)'
        $workflow | Should -Match '\[Pnpm\] \u2713 \$\(\$package\.name\)'
        $workflow | Should -Match '\$package\.PSObject\.Properties\[''installFeature''\]'
        $workflow | Should -Not -Match '\[string\]\$package\.installFeature'
    }

    It 'builds pnpm package evidence safely when optional metadata is absent under StrictMode' {
        Set-StrictMode -Version Latest
        $manifestPath = Join-Path $PSScriptRoot '../../../../windows/pnpm/packages.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $packages = @($manifest.globalPackages)
        $packagesWithoutFeatureMetadata = @(
            $packages | Where-Object { $null -eq $_.PSObject.Properties['installFeature'] }
        )

        $packagesWithoutFeatureMetadata.Count | Should -BeGreaterThan 0

        $successMarker = [string][char]0x2713
        $markers = @()
        foreach ($package in $packages) {
            $installFeature = $package.PSObject.Properties['installFeature']
            if ($null -eq $installFeature -or [string]::IsNullOrWhiteSpace([string]$installFeature.Value)) {
                $markers += "[Pnpm] $successMarker $($package.name)"
            }
        }

        $markers.Count | Should -BeGreaterThan 0
    }

    It 'requires every package included by the normal Winget user phase, including verify-only CI skips' {
        $workflow = $script:workflowLines -join "`n"
        $installerJob = [regex]::Match(
            $workflow,
            '(?ms)^  windows-installer:\s*\r?\n(?<job>.*?)(?=^  [a-zA-Z0-9_-]+:|\z)'
        ).Groups['job'].Value
        $expectedPackageBlock = [regex]::Match(
            $installerJob,
            '(?s)\$expectedWindowsPackageIds\s*=\s*@\((?<block>.*?)\)\s*\n\s*if \(\$expectedWindowsPackageIds.Count'
        ).Groups['block'].Value

        $expectedPackageBlock | Should -Not -Be ''
        $expectedPackageBlock | Should -Match '\$requiresAdmin'
        $expectedPackageBlock | Should -Match '\$installFeature'
        $expectedPackageBlock | Should -Match '\$skipInstall'
        $expectedPackageBlock | Should -Not -Match 'ciSkipInstall'

        $installerJob | Should -Match '(?s)\$npmGlobalPrefix\s*=.*?\$npmPnpmShim\s*=\s*Join-Path \$npmGlobalPrefix ''pnpm\.cmd''.*?& \$npmPnpmShim --version'
    }

    It 'runs the full installer in separate parallel PowerShell 5.1 and 7 jobs' {
        $workflow = $script:workflowLines -join "`n"
        $workflow | Should -Match '(?s)windows-installer:.*?max-parallel:\s*2.*?runtime: Windows PowerShell 5\.1\s+version: "5\.1".*?runtime: PowerShell 7\s+version: "7"'
        $workflow | Should -Match '(?s)shell: pwsh.*?\$runtimeCommand = if \(\$expectedRuntime -eq ''5\.1''\) \{ ''powershell\.exe'' \} else \{ ''pwsh\.exe'' \}.*?\$installerE2EScript = @''.*?install\.cmd -NoPause -UserPhaseOnly.*?''@.*?WriteAllText\(\$installerE2EScriptPath.*?-File \$installerE2EScriptPath'
        $workflow | Should -Match '\$runtimePath = \[string\]\$runtimeExecutable\.Source'
        $workflow | Should -Match '& \$runtimePath -NoLogo -NoProfile -ExecutionPolicy Bypass -File \$installerE2EScriptPath'
        $workflow | Should -Match 'Remove-Item -LiteralPath \$installerE2EScriptPath -Force -ErrorAction SilentlyContinue'
        $workflow | Should -Not -Match 'EncodedCommand.*installerE2EScript'
        $workflow | Should -Match '\$expectedMajorVersion = if \(\$expectedVersion -eq ''5\.1''\) \{ 5 \} else \{ 7 \}'
        $workflow | Should -Match 'Using Windows PowerShell'
        $workflow | Should -Match 'PowerShell 7 installer E2E unexpectedly used the Windows PowerShell 5\.1 path'
        $workflow | Should -Match 'Falling back to Windows PowerShell'
        $workflow | Should -Match '\$isWindowsPowerShell -and \$out -notmatch ''Using Windows PowerShell'''
        $workflow | Should -Match '-not \$isWindowsPowerShell -and \$out -match ''\(Using Windows PowerShell\|Falling back to Windows PowerShell\)'''
    }

    It 'preserves the installer process exit code and full output through the success assertion' {
        $workflow = $script:workflowLines -join "`n"
        $workflow | Should -Match '(?s)\$output = & cmd\.exe /d /c install\.cmd -NoPause -UserPhaseOnly.*?\$exitCode = \$LASTEXITCODE'
        $workflow | Should -Match '(?s)Assert-WindowsInstallerSuccess `\s+-Output \$out `\s+-ExitCode \$exitCode'
    }

    It 'attempts both Codex launch probes after validation failures and reports all errors at the end' {
        $workflow = $script:workflowLines -join "`n"
        $installerJob = [regex]::Match(
            $workflow,
            '(?ms)^  windows-installer:\s*\r?\n(?<job>.*?)(?=^  [a-zA-Z0-9_-]+:|\z)'
        ).Groups['job'].Value

        $installerJob | Should -Match '(?s)\$validationErrors\s*=.*?try\s*\{[\s\S]*?\$expectedVersion\s*=.*?Could not seed the ChatGPT Classic uninstall E2E[\s\S]*?Assert-WindowsInstallerSuccess'
        $installerJob | Should -Match '(?s)catch\s*\{[\s\S]*?\$validationErrors\.Add'
        $installerJob | Should -Match '(?s)finally\s*\{[\s\S]*?Codex CLI.*?try\s*\{[\s\S]*?--help[\s\S]*?catch\s*\{[\s\S]*?\$validationErrors\.Add'
        $installerJob | Should -Match '(?s)finally\s*\{[\s\S]*?code-mode host.*?try\s*\{[\s\S]*?--help[\s\S]*?catch\s*\{[\s\S]*?\$validationErrors\.Add'
        $installerJob | Should -Match '(?s)finally\s*\{[\s\S]*?Codex CLI[\s\S]*?code-mode host'
        $installerJob | Should -Match '(?s)if\s*\(\$validationErrors\.Count\s*-gt\s*0\)[\s\S]*?\$failureSummary\s*=\s*"Windows installer E2E validation failed:'
        $installerJob | Should -Match '(?s)\$failureSummary\s*=.*?\$validationErrors\s*-join'
        $installerJob | Should -Match 'Write-Host \$failureSummary -ForegroundColor Red'
        $installerJob | Should -Match '(?m)^\s*throw \$failureSummary\s*$'
    }

    It 'continues independent fatal validation groups after an installer assertion fails' {
        $workflow = $script:workflowLines -join "`n"
        $installerJob = [regex]::Match(
            $workflow,
            '(?ms)^  windows-installer:\s*\r?\n(?<job>.*?)(?=^  [a-zA-Z0-9_-]+:|\z)'
        ).Groups['job'].Value

        $installerJob | Should -Match '(?s)function Invoke-WindowsE2EValidation[\s\S]*?try\s*\{\s*& \$Validation[\s\S]*?catch\s*\{[\s\S]*?\$validationErrors\.Add'
        $installerJob | Should -Match "Invoke-WindowsE2EValidation -Name 'installer evidence'"
        $installerJob | Should -Match "Invoke-WindowsE2EValidation -Name 'WinGet package inventory'"
        $installerJob | Should -Match "Invoke-WindowsE2EValidation -Name 'pnpm bootstrap'"
        $installerJob | Should -Match "Invoke-WindowsE2EValidation -Name 'ChatGPT Classic removal'"
        $installerJob | Should -Match "Invoke-WindowsE2EValidation -Name 'Codex package structure'"
        $installerJob | Should -Match "Invoke-WindowsE2EValidation -Name 'required command smoke tests'"
        $installerJob | Should -Match "Get-Command -Name 'op.exe' -CommandType Application -ErrorAction Stop"
        $installerJob | Should -Match '(?s)\$onePasswordPackagesPath\s*=.*?AgileBits\.1Password\.CLI_\*'
        $installerJob | Should -Match '(?s)\$resolvedOnePasswordPath\s*=\s*Get-ExternalCommandPath -CommandInfo \$resolvedOnePassword.*?Get-FileHash -LiteralPath \$onePasswordExecutablePath -Algorithm SHA256.*?Get-FileHash -LiteralPath \$resolvedOnePasswordPath -Algorithm SHA256'
        $installerJob | Should -Match 'Persisted user PATH does not identify an installed AgileBits\.1Password\.CLI package directory'
        $installerJob | Should -Match 'PATH-resolved op\.exe does not match the configured WinGet package binary'
        $installerJob | Should -Match 'PATH-resolved pnpm is not the npm-installed pnpm shim'
        $installerJob | Should -Match '(?s)\$onePasswordUserPathEntries\s*=.*?\$onePasswordPackageDirectory\s*='
        $installerJob | Should -Match '& \$resolvedOnePasswordPath --version'
        $installerJob | Should -Match 'Update-ProcessEnvironmentPath -ExcludePath \$runnerPnpmDirectories'
        $installerJob | Should -Match 'Post-install PATH exceeds the cmd\.exe command environment limit'
        $installerJob | Should -Match 'winget source list failed \(exit=\$wingetSourcesExitCode\)'
        $installerJob | Should -Match 'Unable to inspect ChatGPT Classic E2E seed state'
        $installerJob | Should -Match '(?s)\$resolvedCommand\s*=\s*Get-Command -Name \$requiredCommand\.Name -CommandType Application -ErrorAction SilentlyContinue\s*\|\s*Select-Object -First 1'
        $installerJob | Should -Match 'Codex PATH shim does not match the selected installed package executable'
        $installerJob | Should -Not -Match 'onePasswordPackageSearchPath|pnpm resolved outside the npm global prefix'
    }

    It 'does not retain temporary formatter artifact steps' {
        $workflow = $script:workflowLines -join "`n"
        $workflow | Should -Not -Match 'Generate canonical formatter patch for local review'
        $workflow | Should -Not -Match 'Upload canonical formatter output for local review'
    }

    It 'seeds and verifies removal of ChatGPT Classic in the installer E2E' {
        $workflow = $script:workflowLines -join "`n"
        $workflow | Should -Match 'winget install --id 9NT1R1C2HH7J'
        $workflow | Should -Match 'RETIRED_PACKAGE_CLEANUP: id=9NT1R1C2HH7J status=\(removed\|absent\)'
        $workflow | Should -Match 'winget list --id 9NT1R1C2HH7J'
        $workflow | Should -Match 'winget list --id 9NT1R1C2HH7J --exact --source msstore --accept-source-agreements --disable-interactivity'
        $workflow | Should -Match 'ChatGPT Classic is still installed after cleanup'
    }
}
