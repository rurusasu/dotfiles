BeforeAll {
    . (Join-Path $PSScriptRoot '../../ci/Assert-WezTermInstallEvidence.ps1')

    function New-WezTermValidationScopeHarness {
        param([string]$Directory)

        $repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
        $tokens = $null
        $parseErrors = $null
        $outerAst = [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $repositoryRoot 'scripts/powershell/ci/Invoke-WindowsInstallerE2E.ps1'),
            [ref]$tokens, [ref]$parseErrors
        )
        $embedded = $outerAst.Find({
                param($node)
                $node -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                $node.StringConstantType -eq 'SingleQuotedHereString'
            }, $true)
        $innerAst = [System.Management.Automation.Language.Parser]::ParseInput($embedded.Value, [ref]$tokens, [ref]$parseErrors)
        $validationFunction = $innerAst.Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Invoke-WindowsE2EValidation'
            }, $true)
        $validationCalls = @($innerAst.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq 'Invoke-WindowsE2EValidation'
                }, $true))
        $inventory = $validationCalls | Where-Object { $_.CommandElements[2].Value -eq 'WinGet package inventory' }
        $wezterm = $validationCalls | Where-Object { $_.CommandElements[2].Value -eq 'WezTerm install PATH and version' }

        # Feed the real full manifest's eligible inventory at the installer-output
        # boundary. The validation function, both blocks, assertions and version
        # wrapper are the shipped code, executed in a fresh PowerShell process.
        $manifest = Get-Content -LiteralPath (Join-Path $repositoryRoot 'windows/winget/packages.json') -Raw | ConvertFrom-Json
        $eligibleIds = @($manifest.Sources | ForEach-Object { $_.Packages } | Where-Object {
                -not $_.PSObject.Properties['requiresAdmin'].Value -and
                -not $_.PSObject.Properties['skipInstall'].Value
            } | ForEach-Object PackageIdentifier | Sort-Object -Unique)
        $output = @('Total: 1 | Success: 1 | Failure: 0') + @(
            "[Winget] CI_VERIFICATION_INVENTORY: $($eligibleIds -join '|')"
        ) + @($eligibleIds | ForEach-Object { "[Winget] $([char]0x2713) $_" }) + @(
            '[Winget] PACKAGE_PHASE: package=wez.wezterm phase=install status=started timeoutSeconds=900'
            '[Winget] PACKAGE_PHASE: package=wez.wezterm phase=install status=completed elapsedMs=1000 exitCode=0 exitCodeHex=00000000'
            '[Winget] PACKAGE_PHASE: package=wez.wezterm phase=path status=completed elapsedMs=10'
            '[Winget] PACKAGE_PHASE: command=wezterm phase=verify status=completed elapsedMs=100 exitCode=0'
        )
        $outputPath = Join-Path $Directory 'installer-output.txt'
        $output | Set-Content -LiteralPath $outputPath -Encoding UTF8
        $harnessPath = Join-Path $Directory 'validation-scope.ps1'
        $harness = @'
param([string]$RepositoryRoot, [string]$OutputPath, [string]$FixtureBin)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:GITHUB_WORKSPACE = $RepositoryRoot
if ($FixtureBin) { $env:PATH = $FixtureBin + [System.IO.Path]::PathSeparator + $env:PATH }
$validationErrors = [System.Collections.Generic.List[string]]::new()
$out = Get-Content -LiteralPath $OutputPath -Raw
. (Join-Path $RepositoryRoot 'scripts/powershell/lib/Invoke-ExternalCommand.ps1')
'@
        @($harness, $validationFunction.Extent.Text, $inventory.Extent.Text, $wezterm.Extent.Text,
            'if ($validationErrors.Count -gt 0) { throw ($validationErrors -join " | ") }') -join "`n" |
            Set-Content -LiteralPath $harnessPath -Encoding UTF8
        return @{ RepositoryRoot = $repositoryRoot; HarnessPath = $harnessPath; OutputPath = $outputPath }
    }
}

Describe 'Assert-WezTermInstallEvidence' {
    BeforeEach {
        $script:evidence = @'
[Winget] PACKAGE_PHASE: package=wez.wezterm phase=install status=started timeoutSeconds=900
[Winget] PACKAGE_PHASE: package=wez.wezterm phase=install status=completed elapsedMs=1000 exitCode=0 exitCodeHex=00000000
[Winget] PACKAGE_PHASE: package=wez.wezterm phase=path status=started
[Winget] PACKAGE_PHASE: package=wez.wezterm phase=path status=completed elapsedMs=10
[Winget] PACKAGE_PHASE: command=wezterm phase=verify status=started executable=wezterm timeoutSeconds=900
[Winget] PACKAGE_PHASE: command=wezterm phase=verify status=completed elapsedMs=100 exitCode=0
'@
    }

    It 'should accept actual install PATH and version evidence' {
        {
            Assert-WezTermInstallEvidence -Output $script:evidence -PackageId 'wez.wezterm' `
                -VersionOutput 'wezterm 20240203-110809-5046fc22' -VersionExitCode 0
        } | Should -Not -Throw
    }

    It 'should reject missing <Phase> completion evidence' -TestCases @(
        @{ Phase = 'install' }
        @{ Phase = 'path' }
        @{ Phase = 'verify' }
    ) {
        param($Phase)
        $incomplete = ($script:evidence -split "`n" | Where-Object { $_ -notmatch "phase=$Phase status=completed" }) -join "`n"
        {
            Assert-WezTermInstallEvidence -Output $incomplete -PackageId 'wez.wezterm' `
                -VersionOutput 'wezterm 20240203-110809-5046fc22' -VersionExitCode 0
        } | Should -Throw '*phase evidence*'
    }

    It 'should reject nonzero install or verification exits even with valid version output' -TestCases @(
        @{ Phase = 'install' }
        @{ Phase = 'verify' }
    ) {
        param($Phase)
        $failed = $script:evidence -replace "(phase=$Phase status=completed elapsedMs=\d+ exitCode=)0", '${1}124'
        {
            Assert-WezTermInstallEvidence -Output $failed -PackageId 'wez.wezterm' `
                -VersionOutput 'wezterm 20240203-110809-5046fc22' -VersionExitCode 0
        } | Should -Throw '*phase evidence*'
    }

    It 'should reject a version result from another command or a failed child process' -TestCases @(
        @{ VersionOutput = 'another-tool 1.2.3'; ExitCode = 0 }
        @{ VersionOutput = 'wezterm 20240203-110809-5046fc22'; ExitCode = 127 }
    ) {
        param($VersionOutput, $ExitCode)
        {
            Assert-WezTermInstallEvidence -Output $script:evidence -PackageId 'wez.wezterm' `
                -VersionOutput $VersionOutput -VersionExitCode $ExitCode
        } | Should -Throw '*fresh PATH command*'
    }

    It 'should reject version and PATH evidence that preceded installation' {
        $lines = @($script:evidence -split "`n")
        $reordered = (@($lines[2..5]) + @($lines[0..1])) -join "`n"
        {
            Assert-WezTermInstallEvidence -Output $reordered -PackageId 'wez.wezterm' `
                -VersionOutput 'wezterm 20240203-110809-5046fc22' -VersionExitCode 0
        } | Should -Throw '*phase evidence*'
    }

    It 'should validate WezTerm after inventory in independent StrictMode child scopes' {
        $harness = New-WezTermValidationScopeHarness -Directory $TestDrive
        $fixtureBin = Join-Path $TestDrive 'native-bin'
        New-Item -ItemType Directory -Path $fixtureBin | Out-Null
        if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
            $fixtureSource = Join-Path $TestDrive 'wezterm.cs'
            'class WezTermFixture { static int Main(string[] args) { if (args.Length != 1 || args[0] != "--version") return 64; System.Console.WriteLine("wezterm 20240203-110809-5046fc22"); return 0; } }' |
                Set-Content -LiteralPath $fixtureSource -Encoding ASCII
            $compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
            & $compiler /nologo /target:exe "/out:$(Join-Path $fixtureBin 'wezterm.exe')" $fixtureSource
            $LASTEXITCODE | Should -Be 0
        }
        else {
            $fixtureCommand = Join-Path $fixtureBin 'wezterm'
            "#!/bin/sh`nprintf 'wezterm 20240203-110809-5046fc22\n'`n" |
                Set-Content -LiteralPath $fixtureCommand -Encoding UTF8
            & chmod +x $fixtureCommand
        }
        $shellPath = (Get-Process -Id $PID).Path
        $validationOutput = @(& $shellPath -NoLogo -NoProfile -File $harness.HarnessPath `
                -RepositoryRoot $harness.RepositoryRoot -OutputPath $harness.OutputPath -FixtureBin $fixtureBin 2>&1)
        $validationExitCode = $LASTEXITCODE

        $validationExitCode | Should -Be 0 -Because ($validationOutput -join "`n")
        ($validationOutput -join "`n") | Should -Match 'WEZTERM_E2E: .*package=wez\.wezterm .*exitCode=0 version=wezterm 20240203-110809-5046fc22'
    }
}
