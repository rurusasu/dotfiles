BeforeAll {
    $script:runner = Join-Path $PSScriptRoot 'Invoke-Tests.ps1'
    $script:runtime = (Get-Process -Id $PID).Path

    function Invoke-TestPrerequisiteProbe {
        param([string]$MissingDependency = '')

        $fixture = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $fixture -Force | Out-Null
        "Describe 'fixture' { It 'should pass' { 1 | Should -Be 1 } }" |
            Set-Content -LiteralPath (Join-Path $fixture 'Fixture.Tests.ps1')
        $bootstrap = Join-Path $fixture 'bootstrap.ps1'
        @'
param($Runner, $Fixture, $ModulePathsBase64, $MissingDependency)
$ErrorActionPreference = 'Stop'
Import-Module Microsoft.PowerShell.Management, Microsoft.PowerShell.Utility
$env:PSModulePath = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ModulePathsBase64))
$env:FIXTURE_NETWORK_MARKER = Join-Path $Fixture 'unexpected-acquisition.txt'
function Stop-UnexpectedAcquisition {
    Set-Content -LiteralPath $env:FIXTURE_NETWORK_MARKER 'called'
    throw 'Tests must not acquire dependencies'
}
function Find-Module { Stop-UnexpectedAcquisition }
function Install-Module { Stop-UnexpectedAcquisition }
function Save-Module { Stop-UnexpectedAcquisition }
function Install-PackageProvider { Stop-UnexpectedAcquisition }
function Invoke-RestMethod { Stop-UnexpectedAcquisition }
function Invoke-WebRequest { Stop-UnexpectedAcquisition }
if ($MissingDependency -in @('Pester', 'PSScriptAnalyzer')) {
    $env:PSModulePath = Join-Path $Fixture 'empty-modules'
    New-Item -ItemType Directory -Path $env:PSModulePath | Out-Null
}
if ($MissingDependency -eq 'PSScriptAnalyzer') {
    . (Join-Path (Split-Path -Parent $Runner) 'support/Resolve-TestModule.ps1')
    Resolve-TestModule -Name PSScriptAnalyzer | Out-Null
    exit 0
}
$target = Join-Path $Fixture 'Fixture.Tests.ps1'
if ($MissingDependency -eq 'task') {
    $env:PATH = $PSHOME + ';' + (Join-Path $env:SystemRoot 'System32')
    $target = Join-Path (Split-Path -Parent $Runner) 'Install.Wsl.Tests.ps1'
}
& $Runner -Path $target -MinimumCoverage 0
exit $LASTEXITCODE
'@ | Set-Content -LiteralPath $bootstrap

        $previousPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            # Exercise native quoting with spaces and a trailing path separator.
            $modulePaths = $env:PSModulePath + [IO.Path]::PathSeparator +
                (Join-Path $fixture 'Modules with spaces') + [IO.Path]::DirectorySeparatorChar
            $modulePathsBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($modulePaths))
            $arguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $bootstrap,
                '-Runner', $script:runner, '-Fixture', $fixture, '-ModulePathsBase64', $modulePathsBase64)
            if ($MissingDependency) { $arguments += @('-MissingDependency', $MissingDependency) }
            $output = @(& $script:runtime @arguments 2>&1)
            $exitCode = $LASTEXITCODE
        }
        finally { $ErrorActionPreference = $previousPreference }
        return [pscustomobject]@{
            ExitCode            = $exitCode
            Output              = $output -join [Environment]::NewLine
            AcquisitionOccurred = Test-Path -LiteralPath (Join-Path $fixture 'unexpected-acquisition.txt')
        }
    }
}

Describe 'PowerShell test prerequisites' {
    It 'should use installed Pester without network access or installation' {
        $result = Invoke-TestPrerequisiteProbe
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.AcquisitionOccurred | Should -BeFalse
        $result.Output | Should -Match 'SUCCESS: All tests passed!'
    }

    It 'should report missing <Dependency> without downloading it' -ForEach @(
        @{ Dependency = 'Pester' }
        @{ Dependency = 'PSScriptAnalyzer' }
        @{ Dependency = 'task' }
    ) {
        $result = Invoke-TestPrerequisiteProbe -MissingDependency $Dependency
        $result.ExitCode | Should -Be 1 -Because $result.Output
        $result.Output | Should -Match ([regex]::Escape("Required test dependency '$Dependency'"))
        $result.AcquisitionOccurred | Should -BeFalse
    }
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
