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
        $successMarker = [string][char]0x2713
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

    It 'runs the full installer in separate parallel PowerShell 5.1 and 7 jobs' {
        $workflow = $script:workflowLines -join "`n"
        $workflow | Should -Match '(?s)windows-installer:.*?max-parallel:\s*2.*?runtime: Windows PowerShell 5\.1\s+version: "5\.1".*?runtime: PowerShell 7\s+version: "7"'
        $workflow | Should -Match '(?s)windows-installer:.*?shell: pwsh.*?install\.cmd -NoPause -UserPhaseOnly'
        $workflow | Should -Match 'Falling back to Windows PowerShell'
        $workflow | Should -Match 'PowerShell 7 installer E2E unexpectedly used the Windows PowerShell 5\.1 fallback'
    }

    It 'preserves the installer process exit code and full output through the success assertion' {
        $workflow = $script:workflowLines -join "`n"
        $workflow | Should -Match '(?s)\$output = & cmd\.exe /d /c install\.cmd -NoPause -UserPhaseOnly.*?\$exitCode = \$LASTEXITCODE'
        $workflow | Should -Match '(?s)Assert-WindowsInstallerSuccess `\s+-Output \$out `\s+-ExitCode \$exitCode'
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
        $workflow | Should -Match 'ChatGPT Classic is still installed after cleanup'
    }
}
