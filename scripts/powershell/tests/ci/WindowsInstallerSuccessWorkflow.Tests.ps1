Describe 'Windows installer success workflow contract' {
    BeforeAll {
        $workflowPath = Join-Path $PSScriptRoot '../../../../.github/workflows/ci-bootstrap.yml'
        $script:workflowLines = @(Get-Content -LiteralPath $workflowPath)
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
        $workflow | Should -Match '\[string\]::IsNullOrWhiteSpace\(\[string\]\$package\.installFeature\)'
    }
}
