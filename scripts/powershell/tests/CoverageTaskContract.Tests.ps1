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

    It 'should pin Pester to v5 and import the selected version' {
        $runner = Get-Content -LiteralPath (Join-Path $script:repoRoot 'scripts/powershell/tests/Invoke-Tests.ps1') -Raw

        $runner | Should -Match '\$pesterV5\s*=\s*Get-Module\s+-ListAvailable\s+-Name\s+Pester'
        $runner | Should -Match '\$_.Version\s+-ge\s+\[Version\]"5\.0\.0"\s+-and\s+\$_.Version\s+-lt\s+\[Version\]"6\.0\.0"'
        $runner | Should -Match 'Install-Module\s+-Name\s+Pester[\s\S]*-MinimumVersion\s+5\.0\.0[\s\S]*-MaximumVersion\s+5\.999\.999'
        $runner | Should -Match 'Import-Module\s+-Name\s+Pester\s+-RequiredVersion\s+\$pesterV5\.Version'
    }
}
