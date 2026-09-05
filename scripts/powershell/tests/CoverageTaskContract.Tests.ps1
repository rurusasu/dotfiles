BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
}

Describe 'PowerShell coverage task contract' {
    It 'should explicitly request coverage without imposing a threshold' {
        $taskfile = Get-Content -LiteralPath (Join-Path $script:repoRoot 'taskfiles/test/taskfile.yml') -Raw
        $coverageTask = [regex]::Match(
            $taskfile,
            '(?ms)^  test:coverage:\r?\n(?<body>.*?)(?=^  [a-z][^\r\n]*:\r?$)'
        )

        $coverageTask.Success | Should -BeTrue
        $coverageTask.Groups['body'].Value | Should -Match ([regex]::Escape('-ShowCoverage'))
        $coverageTask.Groups['body'].Value | Should -Not -Match '-MinimumCoverage\s+[1-9]'
    }

    It 'should use one coverage-request condition for discovery and Pester configuration' {
        $runner = Get-Content -LiteralPath (Join-Path $script:repoRoot 'scripts/powershell/tests/Invoke-Tests.ps1') -Raw

        $runner | Should -Match '\$coverageRequested\s*=\s*\(\$MinimumCoverage\s+-gt\s+0\)\s+-or\s+\$ShowCoverage\s+-or\s+\(-not\s+\[string\]::IsNullOrWhiteSpace\(\$CoverageOutputFile\)\)'
        ([regex]::Matches($runner, 'if\s*\(\$coverageRequested\)')).Count | Should -Be 2
        $runner | Should -Match '\$pesterConfig\.CodeCoverage\.CoveragePercentTarget\s*=\s*\$MinimumCoverage'
        $runner | Should -Match 'if\s*\(\$coverage\s+-lt\s+\$MinimumCoverage\)'
    }
}
