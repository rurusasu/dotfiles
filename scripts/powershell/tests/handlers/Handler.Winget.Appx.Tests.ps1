BeforeAll {
    Set-StrictMode -Version Latest
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.Winget.ps1
    $script:realBoundedExternalCommand = (Get-Command Invoke-ExternalCommandWithTimeout).ScriptBlock
    if (-not (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
        function global:Get-AppxPackage { param([string]$Name) $null = $Name; return $null }
    }
}

Describe 'WingetHandler direct AppX installer' {
    BeforeEach {
        $script:originalTemp = $env:TEMP
        $script:originalArchitecture = $env:PROCESSOR_ARCHITECTURE
        $script:originalWowArchitecture = $env:PROCESSOR_ARCHITEW6432
        $script:originalTimeout = $env:DOTFILES_INSTALL_TIMEOUT_SECONDS
        $env:TEMP = Join-Path $TestDrive 'downloads'
        $env:PROCESSOR_ARCHITECTURE = 'AMD64'
        $env:PROCESSOR_ARCHITEW6432 = $null
        $env:DOTFILES_INSTALL_TIMEOUT_SECONDS = $null
        New-Item -ItemType Directory -Path $env:TEMP -Force | Out-Null
        $script:appLocation = Join-Path $TestDrive 'registered app'
        New-Item -ItemType Directory -Path $script:appLocation -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:appLocation 'Dia.exe') -Value 'fixture'
        Set-Content -LiteralPath (Join-Path $script:appLocation 'AppxManifest.xml') -Value '<Package><Applications><Application Id="Dia" Executable="Dia.exe" /></Applications></Package>'
        $script:registration = [pscustomobject]@{
            Name = 'Example.Dia'; PackageFamilyName = 'Example.Dia_testpublisher'
            Publisher = 'CN=Fixture'; Version = '1.1.0.6'; Architecture = 'X64'
            InstallLocation = $script:appLocation
        }
        $script:registered = $false
        $script:dependencyRegistration = $null
        $script:registerAfterInstall = $true
        $script:nativeExit = 0
        $script:mainHash = 'ab' * 32
        $script:dependencyHash = 'cd' * 32
        $script:downloaded = [System.Collections.Generic.List[string]]::new()
        $script:downloadTimeouts = [System.Collections.Generic.List[int]]::new()
        $script:deploymentScript = ''
        $script:nativeCommand = ''
        $script:nativeArguments = @()
        $script:nativeTimeout = -1
        $script:handler = [WingetHandler]::new()
        $script:package = [pscustomobject]@{
            Id = 'Example.Dia'; SourceName = 'direct'; InstallTimeoutSeconds = 73
            DirectInstaller = [pscustomobject]@{
                type = 'appx'; name = 'Example.Dia'; packageFamilyName = 'Example.Dia_testpublisher'
                publisher = 'CN=Fixture'; version = '1.1.0.6'; architecture = 'x64'; executable = 'Dia.exe'
                url = 'https://example.invalid/Dia.x64.msix'; sha256 = ('ab' * 32)
                dependencies = @([pscustomobject]@{ url = 'https://example.invalid/vclibs.appx'; sha256 = ('cd' * 32) })
            }
            VerifyCommand   = [pscustomobject]@{ type = 'appxLaunchTarget'; command = 'Example.Dia'; args = @('Example.Dia_testpublisher!Dia') }
        }
        Mock Write-Host {}
        Mock Get-AppxPackage {
            param($Name)
            if ($Name -eq 'Example.Framework') { $script:dependencyRegistration }
            elseif ($Name -eq 'Example.Dia' -and $script:registered) { $script:registration }
        }
        Mock Invoke-Winget { throw 'Direct AppX must not call WinGet' }
        Mock Invoke-WebRequest {
            param($Uri, $OutFile, $TimeoutSec, $ConnectionTimeoutSeconds)
            $script:downloaded.Add([string]$Uri)
            $script:downloadTimeouts.Add([int]$(if ($null -ne $ConnectionTimeoutSeconds) { $ConnectionTimeoutSeconds } else { $TimeoutSec }))
            Set-Content -LiteralPath $OutFile -Value 'fixture download'
        }
        Mock Get-FileHash {
            param($LiteralPath)
            $hash = if ((Split-Path -Leaf $LiteralPath) -like 'dependency-*') { $script:dependencyHash } else { $script:mainHash }
            [pscustomobject]@{ Hash = $hash.ToUpperInvariant() }
        }
        Mock Invoke-ExternalCommandWithTimeout {
            param($Command, $Arguments, $TimeoutSeconds)
            $script:nativeCommand = $Command
            $script:nativeArguments = @($Arguments)
            $script:nativeTimeout = $TimeoutSeconds
            $script:deploymentScript = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($Arguments[-1]))
            $script:registered = $script:registerAfterInstall
            $global:LASTEXITCODE = $script:nativeExit
            'deployment output'
        }
        Mock Invoke-NativeCommand {
            param($Command, $Arguments)
            $script:nativeCommand = $Command
            $script:nativeArguments = @($Arguments)
            $script:deploymentScript = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($Arguments[-1]))
            $script:registered = $script:registerAfterInstall
            $global:LASTEXITCODE = $script:nativeExit
            'deployment output'
        }
    }

    AfterEach {
        $env:TEMP = $script:originalTemp
        $env:PROCESSOR_ARCHITECTURE = $script:originalArchitecture
        $env:PROCESSOR_ARCHITEW6432 = $script:originalWowArchitecture
        $env:DOTFILES_INSTALL_TIMEOUT_SECONDS = $script:originalTimeout
    }

    It 'should accept only the matching registered package with a current version and real executable' {
        $script:registered = $true
        $script:handler.TestDirectInstallerCurrent($script:package) | Should -BeTrue
        $script:registration.Version = '1.2.0.0'
        $script:handler.TestDirectInstallerCurrent($script:package) | Should -BeTrue
        $script:registration.Version = '1.0.0.0'
        $script:handler.TestDirectInstallerCurrent($script:package) | Should -BeFalse
        $script:registration.Version = '1.1.0.6'
        $script:registration.Publisher = 'CN=Other'
        $script:handler.TestDirectInstallerCurrent($script:package) | Should -BeFalse
        $script:registration.Publisher = 'CN=Fixture'
        $script:registration.PackageFamilyName = 'Example.Dia_other'
        $script:handler.TestDirectInstallerCurrent($script:package) | Should -BeFalse
        $script:registration.PackageFamilyName = 'Example.Dia_testpublisher'
        $script:registration.Architecture = 'Arm64'
        $script:handler.TestDirectInstallerCurrent($script:package) | Should -BeFalse
        $script:registration.Architecture = 'X64'
        Remove-Item -LiteralPath (Join-Path $script:appLocation 'Dia.exe')
        $script:handler.TestDirectInstallerCurrent($script:package) | Should -BeFalse
    }

    It 'should deploy hash-checked official packages through bounded Windows PowerShell and verify registration' {
        $output = @($script:handler.InvokePackageInstall($script:package, @()))
        $global:LASTEXITCODE | Should -Be 0
        $script:handler.LastInstallSucceeded | Should -BeTrue
        $output | Should -Contain 'deployment output'
        $script:downloaded.Count | Should -Be 2
        @($script:downloadTimeouts | Select-Object -Unique) | Should -Be @(73)
        $script:nativeTimeout | Should -Be 73
        $script:nativeCommand | Should -Be (Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe')
        $script:deploymentScript | Should -Match 'Add-AppxPackage'
        $script:deploymentScript | Should -Match '-DependencyPath'
        $script:deploymentScript | Should -Not -Match 'ForceApplicationShutdown|ForceUpdateFromAnyVersion'
        Should -Invoke Invoke-Winget -Times 0
        @(Get-ChildItem -LiteralPath $env:TEMP).Count | Should -Be 0
    }

    It 'should emit Japanese child-process errors as UTF-8 without installing a package' {
        $null = $script:handler.InvokePackageInstall($script:package, @())
        # Run the generated child script with harmless boundary replacements.
        # The real process capture must decode its Japanese stderr correctly.
        $harness = "function Import-Module {}; function Add-AppxPackage { [Console]::Error.WriteLine('日本語の失敗'); exit 7 }; " + $script:deploymentScript
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($harness))
        $output = @(& $script:realBoundedExternalCommand -Command $script:nativeCommand -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded) -TimeoutSeconds 10)
        $global:LASTEXITCODE | Should -Be 7
        ($output -join "`n") | Should -Match '日本語の失敗'
    }

    It 'should suppress child AppX progress XML and capture only deployment text' {
        $null = $script:handler.InvokePackageInstall($script:package, @())
        $harness = "function Import-Module {}; function Add-AppxPackage { [Console]::WriteLine([string]`$ProgressPreference); Write-Progress -Activity 'Fixture deployment' -Status 'Working' -PercentComplete 50; Write-Output 'Deployment complete' }; " + $script:deploymentScript
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($harness))
        $arguments = @($script:nativeArguments)
        $arguments[-1] = $encoded
        $output = @(& $script:realBoundedExternalCommand -Command $script:nativeCommand -Arguments $arguments -TimeoutSeconds 10)
        $global:LASTEXITCODE | Should -Be 0
        ($output -join "`n") | Should -Be "SilentlyContinue`nDeployment complete"
        $script:nativeArguments | Should -Contain '-OutputFormat'
        $script:nativeArguments | Should -Contain 'Text'
    }

    Context 'Registered dependency selection' {
        BeforeEach {
            $script:package.DirectInstaller.dependencies[0] = [pscustomobject]@{
                url = 'https://example.invalid/vclibs.appx'; sha256 = ('cd' * 32)
                name = 'Example.Framework'; packageFamilyName = 'Example.Framework_fixture'
                publisher = 'CN=Framework'; version = '14.0.33728.0'; architecture = 'x64'
            }
            $script:dependencyRegistration = [pscustomobject]@{
                Name = 'Example.Framework'; PackageFamilyName = 'Example.Framework_fixture'
                Publisher = 'CN=Framework'; Version = '14.0.33728.0'; Architecture = 'X64'; Status = 'Ok'
            }
        }

        It 'should skip downloading and redeploying a matching dependency version <Version>' -TestCases @(
            @{ Version = '14.0.33728.0' }; @{ Version = '14.0.40000.0' }
        ) {
            param($Version)
            $script:dependencyRegistration.Version = $Version
            $null = $script:handler.InvokePackageInstall($script:package, @())
            $global:LASTEXITCODE | Should -Be 0
            $script:downloaded.Count | Should -Be 1
            $script:downloaded[0] | Should -Be 'https://example.invalid/Dia.x64.msix'
            $script:deploymentScript | Should -Not -Match '-DependencyPath'
        }

        It 'should download the pinned dependency when the registered dependency has <Fault>' -TestCases @(
            @{ Fault = 'an older version'; Property = 'Version'; Value = '14.0.10000.0' }
            @{ Fault = 'a different architecture'; Property = 'Architecture'; Value = 'Arm64' }
            @{ Fault = 'a different publisher'; Property = 'Publisher'; Value = 'CN=Other' }
            @{ Fault = 'a different family'; Property = 'PackageFamilyName'; Value = 'Example.Framework_other' }
            @{ Fault = 'a different name'; Property = 'Name'; Value = 'Other.Framework' }
            @{ Fault = 'an unhealthy status'; Property = 'Status'; Value = 'Modified' }
        ) {
            param($Fault, $Property, $Value)
            $script:dependencyRegistration.$Property = $Value
            $null = $script:handler.InvokePackageInstall($script:package, @())
            $global:LASTEXITCODE | Should -Be 0
            $script:downloaded.Count | Should -Be 2
            $script:deploymentScript | Should -Match '-DependencyPath'
        }

        It 'should download the pinned dependency when no matching registration exists' {
            $script:dependencyRegistration = $null
            $null = $script:handler.InvokePackageInstall($script:package, @())
            $global:LASTEXITCODE | Should -Be 0
            $script:downloaded.Count | Should -Be 2
            $script:deploymentScript | Should -Match '-DependencyPath'
        }
    }

    It 'should skip download and deployment when the matching AppX version <Version> is already current' -TestCases @(
        @{ Version = '1.1.0.6' }; @{ Version = '1.2.0.0' }
    ) {
        param($Version)
        $script:registered = $true
        $script:registration.Version = $Version
        $null = $script:handler.InvokeDirectInstaller($script:package)
        $global:LASTEXITCODE | Should -Be 0
        Should -Invoke Invoke-WebRequest -Times 0
        Should -Invoke Invoke-ExternalCommandWithTimeout -Times 0
    }

    It 'should deploy a current AppX when failed verification requests a forced reinstall' {
        $script:registered = $true
        $script:package | Add-Member -NotePropertyName Force -NotePropertyValue $true
        $null = $script:handler.InvokePackageInstall($script:package, @())
        $global:LASTEXITCODE | Should -Be 0
        $script:downloaded.Count | Should -Be 2
        $script:deploymentScript | Should -Match 'Add-AppxPackage'
        $script:deploymentScript | Should -Not -Match 'ForceUpdateFromAnyVersion'
    }

    It 'should reject a <Artifact> hash mismatch before deployment and clean owned downloads' -TestCases @(
        @{ Artifact = 'main' }; @{ Artifact = 'dependency' }
    ) {
        param($Artifact)
        if ($Artifact -eq 'main') { $script:mainHash = 'ee' * 32 } else { $script:dependencyHash = 'ee' * 32 }
        $output = @($script:handler.InvokeDirectInstaller($script:package))
        $global:LASTEXITCODE | Should -Be 1
        ($output -join ' ') | Should -Match 'hash mismatch'
        Should -Invoke Invoke-ExternalCommandWithTimeout -Times 0
        @(Get-ChildItem -LiteralPath $env:TEMP).Count | Should -Be 0
    }

    It 'should preserve deployment failure exit <ExitCode> and timeout state' -TestCases @(
        @{ ExitCode = 7; TimedOut = $false }; @{ ExitCode = 124; TimedOut = $true }
    ) {
        param($ExitCode, $TimedOut)
        $script:nativeExit = $ExitCode
        $null = $script:handler.InvokePackageInstall($script:package, @())
        $script:handler.LastInstallExitCode | Should -Be $ExitCode
        $script:handler.LastInstallSucceeded | Should -BeFalse
        $script:handler.LastInstallTimedOut | Should -Be $TimedOut
    }

    It 'should fail successful deployment without a real <Missing> registration artifact' -TestCases @(
        @{ Missing = 'package' }; @{ Missing = 'executable' }
    ) {
        param($Missing)
        if ($Missing -eq 'package') { $script:registerAfterInstall = $false }
        else { Remove-Item -LiteralPath (Join-Path $script:appLocation 'Dia.exe') }
        $output = @($script:handler.InvokePackageInstall($script:package, @()))
        $global:LASTEXITCODE | Should -Be 1
        $script:handler.LastInstallSucceeded | Should -BeFalse
        ($output -join ' ') | Should -Match 'registration|executable'
    }

    It 'should reject unsupported ARM64 before download or deployment' {
        $env:PROCESSOR_ARCHITECTURE = 'ARM64'
        $output = @($script:handler.InvokeDirectInstaller($script:package))
        $global:LASTEXITCODE | Should -Be 1
        ($output -join ' ') | Should -Match 'architecture'
        Should -Invoke Invoke-WebRequest -Times 0
        Should -Invoke Invoke-ExternalCommandWithTimeout -Times 0
    }

    It 'should honor the explicit zero timeout through the unbounded native wrapper' {
        $env:DOTFILES_INSTALL_TIMEOUT_SECONDS = '0'
        $null = $script:handler.InvokeDirectInstaller($script:package)
        $global:LASTEXITCODE | Should -Be 0
        @($script:downloadTimeouts | Select-Object -Unique) | Should -Be @(0)
        Should -Invoke Invoke-NativeCommand -Times 1
        Should -Invoke Invoke-ExternalCommandWithTimeout -Times 0
    }

    It 'should import a direct-only source without probing or installing a WinGet catalog package' {
        $repo = Join-Path $TestDrive 'repository'
        $manifestDir = Join-Path $repo 'windows/winget'
        New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
        @{ Sources = @(@{ SourceDetails = @{ Name = 'direct' }; Packages = @(@{
                            PackageIdentifier = $script:package.Id; directInstaller = $script:package.DirectInstaller
                            installTimeoutSeconds = 73; verifyCommand = $script:package.VerifyCommand
                        })
                })
        } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $manifestDir 'packages.json')
        $ctx = [SetupContext]::new($repo)
        $ctx.Options['SkipRetiredPackageCleanup'] = $true
        $result = $script:handler.Apply($ctx)
        $result.Success | Should -BeTrue -Because $result.Message
        Should -Invoke Invoke-Winget -Times 0
    }
}
