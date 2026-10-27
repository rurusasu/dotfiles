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
param($Runner, $Fixture, $MissingDependency)
$ErrorActionPreference = 'Stop'
Import-Module Microsoft.PowerShell.Management, Microsoft.PowerShell.Utility
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
if (-not $MissingDependency) {
    Copy-Item -LiteralPath $Runner -Destination $Fixture
    New-Item -ItemType Directory -Path "$Fixture/support" | Out-Null
    Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $Runner) 'support/Resolve-TestModule.ps1') -Destination "$Fixture/support"
    & (Join-Path $Fixture 'Invoke-Tests.ps1')
    exit $LASTEXITCODE
}
$target = Join-Path $Fixture 'Fixture.Tests.ps1'
if ($MissingDependency -eq 'task') {
    $env:PATH = $PSHOME + ';' + (Join-Path $env:SystemRoot 'System32')
    $target = Join-Path (Split-Path -Parent $Runner) 'Install.Tests.ps1'
}
& $Runner -Path $target
exit $LASTEXITCODE
'@ | Set-Content -LiteralPath $bootstrap

        $previousPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $arguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $bootstrap,
                '-Runner', $script:runner, '-Fixture', $fixture)
            if ($MissingDependency) { $arguments += @('-MissingDependency', $MissingDependency) }
            $output = @(& $script:runtime @arguments 2>&1)
            $exitCode = $LASTEXITCODE
        }
        finally { $ErrorActionPreference = $previousPreference }
        return [pscustomobject]@{
            ExitCode            = $exitCode
            # Child PowerShell can interleave ANSI styling with wrapped diagnostics.
            Output              = [regex]::Replace(($output -join [Environment]::NewLine), '\x1B\[[0-9;]*m', '')
            AcquisitionOccurred = Test-Path -LiteralPath (Join-Path $fixture 'unexpected-acquisition.txt')
        }
    }
}

Describe 'PowerShell test prerequisites' {
    It 'should discover tests by default using installed Pester without acquisition' {
        $result = Invoke-TestPrerequisiteProbe
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.AcquisitionOccurred | Should -BeFalse
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
    It 'should fail when no tests are discovered' {
        $fixture = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $fixture | Out-Null
        $output = & $script:runtime -NoProfile -File $script:runner -Path $fixture 2>&1
        $LASTEXITCODE | Should -Be 1 -Because ($output -join [Environment]::NewLine)
    }

    It 'should reject <FailureKind> even when another test passes' -ForEach @(
        @{ FailureKind = 'discovery errors'; BrokenSource = "Describe 'broken' {" }
        @{ FailureKind = 'container setup errors'; BrokenSource = "BeforeAll { throw 'fixture setup failed' }; Describe 'broken' { It 'cannot run' { 1 | Should -Be 1 } }" }
    ) {
        $fixture = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $fixture | Out-Null
        "Describe 'healthy' { It 'passes' { 1 | Should -Be 1 } }" | Set-Content -LiteralPath (Join-Path $fixture 'Healthy.Tests.ps1')
        $BrokenSource | Set-Content -LiteralPath (Join-Path $fixture 'Broken.Tests.ps1')
        $output = @(& $script:runtime -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script:runner -Path $fixture 2>&1)
        $exitCode = $LASTEXITCODE

        $exitCode | Should -Be 1 -Because ($output -join [Environment]::NewLine)
    }
}

