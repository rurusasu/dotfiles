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

    It 'should exercise the coverage-requested true path and emit coverage XML' {
        $smokePath = Join-Path $TestDrive 'CoverageSmoke.Tests.ps1'
        $coveragePath = Join-Path $TestDrive 'coverage.xml'
        @'
Describe 'coverage smoke' {
    It 'should pass a minimal assertion' {
        $true | Should -BeTrue
    }
}
'@ | Set-Content -LiteralPath $smokePath -Encoding UTF8

        $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
        if ($null -eq $pwsh) {
            Set-ItResult -Skipped -Because 'PowerShell 7 (pwsh) is not installed on this host'
            return
        }
        $runnerPath = Join-Path $script:repoRoot 'scripts/powershell/tests/Invoke-Tests.ps1'
        $childArguments = @(
            '-NoProfile'
            '-File'
            $runnerPath
            '-Path'
            $smokePath
            '-ShowCoverage'
            '-CoverageOutputFile'
            $coveragePath
        )
        $output = & $pwsh.Source @childArguments 2>&1
        $exitCode = $LASTEXITCODE
        $outputText = $output | Out-String
        Write-Host $outputText

        $exitCode | Should -Be 0
        $outputText | Should -Match 'Source Files:\s+7'
        (Test-Path -LiteralPath $coveragePath) | Should -BeTrue
        [xml]$coverageXml = Get-Content -LiteralPath $coveragePath -Raw
        $coverageXml | Should -Not -BeNullOrEmpty
    }
}
