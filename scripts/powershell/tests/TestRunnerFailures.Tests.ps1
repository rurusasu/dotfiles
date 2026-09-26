BeforeAll {
    $script:runner = Join-Path $PSScriptRoot 'Invoke-Tests.ps1'
    $script:runtime = (Get-Process -Id $PID).Path
}

Describe 'PowerShell test runner failure propagation' {
    It 'should reject <FailureKind> even when another test passes' -ForEach @(
        @{ FailureKind = 'discovery errors'; BrokenSource = "Describe 'broken' {" }
        @{ FailureKind = 'container setup errors'; BrokenSource = "BeforeAll { throw 'fixture setup failed' }; Describe 'broken' { It 'cannot run' { 1 | Should -Be 1 } }" }
    ) {
        $fixture = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $fixture | Out-Null
        "Describe 'healthy' { It 'passes' { 1 | Should -Be 1 } }" | Set-Content -LiteralPath (Join-Path $fixture 'Healthy.Tests.ps1')
        $BrokenSource | Set-Content -LiteralPath (Join-Path $fixture 'Broken.Tests.ps1')
        $escapedModules = $env:PSModulePath.Replace("'", "''")
        $escapedRunner = $script:runner.Replace("'", "''")
        $escapedFixture = $fixture.Replace("'", "''")
        $command = "`$env:PSModulePath = '$escapedModules'; & '$escapedRunner' -Path '$escapedFixture' -MinimumCoverage 0"
        $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))

        $output = @(& $script:runtime -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encodedCommand 2>&1)
        $exitCode = $LASTEXITCODE

        $exitCode | Should -Be 1 -Because ($output -join [Environment]::NewLine)
        ($output -join [Environment]::NewLine) | Should -Not -Match 'SUCCESS: All tests passed!'
    }
}
