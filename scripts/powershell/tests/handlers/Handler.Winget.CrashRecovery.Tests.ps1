BeforeAll {
    Set-StrictMode -Version Latest
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../handlers/Handler.Winget.ps1
}

Describe 'Winget Arc crash recovery' {
    BeforeEach {
        $script:handler = [WingetHandler]::new()
        $script:package = [pscustomobject]@{
            Id                    = 'TheBrowserCompany.Arc'
            SourceName            = 'winget'
            InstallTimeoutSeconds = 30
            DirectInstaller       = $null
        }
        $script:arguments = @('install', '-e', '--id', 'TheBrowserCompany.Arc', '--silent', '--source', 'winget')
        $script:attempts = [System.Collections.Generic.List[object]]::new()
        $script:logs = [System.Collections.Generic.List[string]]::new()
        $script:exits = @(-1073740791, 0)
        Mock Write-Host { param($Object) $script:logs.Add([string]$Object) }
        Mock Invoke-Winget {
            param($Arguments, $TimeoutSeconds)
            $index = $script:attempts.Count
            $script:attempts.Add([pscustomobject]@{ Args = @($Arguments); Timeout = $TimeoutSeconds })
            $global:LASTEXITCODE = $script:exits[[Math]::Min($index, $script:exits.Count - 1)]
            if ($index -eq 0) { 'dependency diagnostic: timed out before native crash' } else { 'Arc installer completed' }
        }
    }

    It 'should recover a single Arc native crash using the identical install request' {
        $output = @($handler.InvokePackageInstall($package, $arguments))

        $handler.LastInstallSucceeded | Should -BeTrue
        $handler.LastInstallExitCode | Should -Be 0
        $handler.LastInstallTimedOut | Should -BeFalse
        $script:attempts.Count | Should -Be 2
        $script:attempts[0].Args | Should -Be $arguments
        $script:attempts[1].Args | Should -Be $arguments
        $script:attempts[1].Timeout | Should -BeGreaterThan 0
        $script:attempts[1].Timeout | Should -BeLessThan 30
        ($script:logs -join "`n") | Should -Match 'exitCodeHex=C0000409'
        ($script:logs -join "`n") | Should -Match 'dependency diagnostic: timed out before native crash'
        $output | Should -Not -Contain 'dependency diagnostic: timed out before native crash'
        $output | Should -Contain 'Arc installer completed'
    }

    It 'should preserve an explicit unlimited install budget on the single retry' {
        $originalShared = $env:DOTFILES_INSTALL_TIMEOUT_SECONDS
        try {
            $env:DOTFILES_INSTALL_TIMEOUT_SECONDS = '0'
            $null = $handler.InvokePackageInstall($package, $arguments)

            $handler.LastInstallSucceeded | Should -BeTrue
            $script:attempts.Count | Should -Be 2
            $script:attempts[0].Timeout | Should -BeNullOrEmpty
            $script:attempts[1].Timeout | Should -BeNullOrEmpty
        }
        finally {
            $env:DOTFILES_INSTALL_TIMEOUT_SECONDS = $originalShared
        }
    }

    It 'should fail closed after a repeated crash or different retry failure <FinalExit>' -TestCases @(
        @{ FinalExit = -1073740791 }
        @{ FinalExit = 1 }
        @{ FinalExit = 124 }
    ) {
        param($FinalExit)
        $script:exits = @(-1073740791, $FinalExit)
        $null = $handler.InvokePackageInstall($package, $arguments)

        $handler.LastInstallSucceeded | Should -BeFalse
        $handler.LastInstallExitCode | Should -Be $FinalExit
        $handler.LastInstallTimedOut | Should -Be ($FinalExit -eq 124)
        $script:attempts.Count | Should -Be 2
    }

    It 'should not retry other packages sources or normal outcomes <Id> <Source> <Exit>' -TestCases @(
        @{ Id = 'Other.App'; Source = 'winget'; Exit = -1073740791 }
        @{ Id = 'TheBrowserCompany.Arc'; Source = 'msstore'; Exit = -1073740791 }
        @{ Id = 'TheBrowserCompany.Arc'; Source = 'winget'; Exit = 0 }
        @{ Id = 'TheBrowserCompany.Arc'; Source = 'winget'; Exit = 1 }
        @{ Id = 'TheBrowserCompany.Arc'; Source = 'winget'; Exit = 124 }
        @{ Id = 'TheBrowserCompany.Arc'; Source = 'winget'; Exit = -1073741819 }
    ) {
        param($Id, $Source, $Exit)
        $package.Id = $Id
        $package.SourceName = $Source
        $script:exits = @($Exit)
        $null = $handler.InvokePackageInstall($package, $arguments)

        $handler.LastInstallExitCode | Should -Be $Exit
        $script:attempts.Count | Should -Be 1
    }

    It 'should not restart with an unlimited timeout when the original budget is exhausted' {
        $package.InstallTimeoutSeconds = 1
        Mock Invoke-Winget {
            param($Arguments, $TimeoutSeconds)
            $script:attempts.Add([pscustomobject]@{ Args = $Arguments; Timeout = $TimeoutSeconds })
            Start-Sleep -Milliseconds 1100
            $global:LASTEXITCODE = -1073740791
            'dependency installer ended'
        }
        $null = $handler.InvokePackageInstall($package, $arguments)

        $handler.LastInstallSucceeded | Should -BeFalse
        $script:attempts.Count | Should -Be 1
    }

    Context 'Apply verification and failure accounting' {
        BeforeEach {
            $script:ctx = [SetupContext]::new($TestDrive)
            $ctx.Options['SkipRetiredPackageCleanup'] = $true
            $ctx.Options['WingetProcessOnlyPath'] = $true
            Mock Test-PathExist { $true }
            Mock Update-ProcessEnvironmentPath { }
            Mock Get-ExternalCommand { @{ Source = 'C:\fixture\arc.exe' } }
            Mock Get-JsonContent {
                [pscustomobject]@{
                    Sources = @(
                        [pscustomobject]@{
                            SourceDetails = [pscustomobject]@{ Name = 'winget' }
                            Packages      = @([pscustomobject]@{
                                    PackageIdentifier = 'TheBrowserCompany.Arc'
                                    verifyCommand     = [pscustomobject]@{ command = 'arc'; args = @('--version') }
                                })
                        }
                    )
                }
            }
            $script:verifyExit = 0
            $script:verifyCalls = 0
            Mock Invoke-VerifyCommand {
                $script:verifyCalls++
                $global:LASTEXITCODE = $script:verifyExit
                'Arc fixture'
            }
            Mock Invoke-Winget {
                param($Arguments, $TimeoutSeconds)
                if ($Arguments[0] -eq 'list') {
                    $global:LASTEXITCODE = 0
                    return @('Name Id Version Source', '----------------------')
                }
                $index = $script:attempts.Count
                $script:attempts.Add([pscustomobject]@{ Args = @($Arguments); Timeout = $TimeoutSeconds })
                $global:LASTEXITCODE = $script:exits[[Math]::Min($index, $script:exits.Count - 1)]
                if ($index -eq 0) { 'dependency already installed' } else { 'Arc installer completed' }
            }
        }

        It 'should require successful verification after the recovered installer exits zero <VerifyExit>' -TestCases @(
            @{ VerifyExit = 0 }
            @{ VerifyExit = 1 }
        ) {
            param($VerifyExit)
            $script:verifyExit = $VerifyExit
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be ($VerifyExit -eq 0)
            $script:attempts.Count | Should -Be 2
            $script:verifyCalls | Should -BeGreaterThan 0
        }

        It 'should not accept first-attempt no-op text or an existing verifier after retry failure' {
            $script:exits = @(-1073740791, -1073740791)
            $result = $handler.Apply($ctx)

            $result.Success | Should -BeFalse
            $script:attempts.Count | Should -Be 2
            # The pre-install verifier ran once. A failed recovery must not
            # invoke it again to preserve the old installation as success.
            $script:verifyCalls | Should -Be 1
        }
    }
}
