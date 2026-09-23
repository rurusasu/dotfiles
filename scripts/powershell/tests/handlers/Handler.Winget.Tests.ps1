BeforeAll {
    Set-StrictMode -Version Latest
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.Winget.ps1

    if (-not (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
        function global:Get-AppxPackage {
            param([string]$Name)
            $null = $Name
            return $null
        }
    }
}

Describe 'WingetHandler' {
    BeforeEach {
        $script:origUserProfileForWingetTests = $env:USERPROFILE
        $script:origLocalAppDataForWingetTests = $env:LOCALAPPDATA
        $env:USERPROFILE = Join-Path $TestDrive "UserProfile"
        $script:handler = [WingetHandler]::new()
        $script:ctx = [SetupContext]::new((Join-Path $TestDrive "dotfiles"))
        $retiredManifestDirectory = Join-Path $ctx.DotfilesPath 'windows\winget'
        New-Item -ItemType Directory -Path $retiredManifestDirectory -Force | Out-Null
        '{"packages":[]}' | Set-Content -LiteralPath (Join-Path $retiredManifestDirectory 'retired-packages.json') -Encoding UTF8
        Mock Test-Path {
            param($Path, $LiteralPath, $PathType)

            $candidate = if ($null -ne $LiteralPath) { $LiteralPath } else { $Path }
            if ($null -eq $candidate) { return $false }

            $candidatePath = [string]$candidate
            switch ([string]$PathType) {
                "Leaf" { return [System.IO.File]::Exists($candidatePath) }
                "Container" { return [System.IO.Directory]::Exists($candidatePath) }
                default {
                    return [System.IO.File]::Exists($candidatePath) -or
                    [System.IO.Directory]::Exists($candidatePath)
                }
            }
        }
        Mock Update-ProcessEnvironmentPath { }
    }

    AfterEach {
        $env:USERPROFILE = $script:origUserProfileForWingetTests
        $env:LOCALAPPDATA = $script:origLocalAppDataForWingetTests
    }

    Context 'RemoveRetiredPackages' {
        It 'should fail instead of silently skipping cleanup when the retired manifest is missing' {
            { $handler.RemoveRetiredPackages($TestDrive) } | Should -Throw '*retired package manifest is missing*'
        }

        It 'should uninstall only the exact retired package from its declared source' {
            $retiredManifest = Join-Path $TestDrive 'retired-packages.json'
            @{
                packages = @(
                    @{
                        id     = '9NT1R1C2HH7J'
                        name   = 'ChatGPT Classic'
                        source = 'msstore'
                    }
                )
            } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $retiredManifest -Encoding UTF8

            Mock Invoke-Winget {
                param([string[]]$Arguments)
                $script:retiredPackageArgs = $Arguments
                $global:LASTEXITCODE = 0
                return 'Successfully uninstalled'
            }

            $removedCount = $handler.RemoveRetiredPackages($TestDrive)

            $removedCount | Should -Be 1
            $script:retiredPackageArgs | Should -Contain '--exact'
            $script:retiredPackageArgs | Should -Contain '9NT1R1C2HH7J'
            $script:retiredPackageArgs | Should -Contain '--source'
            $script:retiredPackageArgs | Should -Contain 'msstore'
            $script:retiredPackageArgs | Should -Contain '--silent'
        }

        It 'should apply the retired package manifest from the configured dotfiles root' {
            $manifestDirectory = Join-Path $ctx.DotfilesPath 'windows\winget'
            New-Item -ItemType Directory -Path $manifestDirectory -Force | Out-Null
            @{ Sources = @() } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $manifestDirectory 'packages.json') -Encoding UTF8
            @{
                packages = @(
                    @{
                        id     = '9NT1R1C2HH7J'
                        name   = 'ChatGPT Classic'
                        source = 'msstore'
                    }
                )
            } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $manifestDirectory 'retired-packages.json') -Encoding UTF8

            Mock Invoke-Winget {
                param([string[]]$Arguments)
                $script:retiredPackageArgs = $Arguments
                $global:LASTEXITCODE = 0
                return 'Successfully uninstalled'
            }

            $ctx.Options['WingetMode'] = 'import'
            $result = $handler.Apply($ctx)

            $result.Success | Should -BeTrue
            $script:retiredPackageArgs | Should -Contain 'uninstall'
            $script:retiredPackageArgs | Should -Contain '9NT1R1C2HH7J'
        }
    }

    Context 'TestPackageVerification - package-specific installed artifact probes' {
        It 'should execute a portable WinGet link directly instead of resolving a same-named rustup shim' {
            $script:origLocalAppDataForWingetTests = $env:LOCALAPPDATA
            $env:LOCALAPPDATA = Join-Path $TestDrive 'LocalAppData'
            $linksPath = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'
            New-Item -ItemType Directory -Path $linksPath -Force | Out-Null
            $expectedCommand = Join-Path $linksPath 'rust-analyzer.exe'
            New-Item -ItemType File -Path $expectedCommand -Force | Out-Null

            Mock Invoke-VerifyCommand {
                param($Command, $Arguments)
                $script:verifiedCommand = $Command
                $script:verifiedArguments = $Arguments
                $global:LASTEXITCODE = 0
                return 'rust-analyzer 1.0.0'
            }

            $verified = $handler.TestPackageVerification([PSCustomObject]@{
                    type    = 'portableLinkCommand'
                    command = 'rust-analyzer.exe'
                    args    = @('--version')
                })

            $verified | Should -BeTrue
            $script:verifiedCommand | Should -Be $expectedCommand
            $script:verifiedArguments | Should -Be @('--version')
        }

        It 'should reject a portable WinGet link probe when the package link is missing' {
            $script:origLocalAppDataForWingetTests = $env:LOCALAPPDATA
            $env:LOCALAPPDATA = Join-Path $TestDrive 'MissingLocalAppData'
            Mock Invoke-VerifyCommand { throw 'A missing package link must not run another PATH command' }

            $verified = $handler.TestPackageVerification([PSCustomObject]@{
                    type    = 'portableLinkCommand'
                    command = 'rust-analyzer.exe'
                    args    = @('--version')
                })

            $verified | Should -BeFalse
            Should -Invoke Invoke-VerifyCommand -Times 0
        }

        It 'should verify a Windows application from its AppX family and version without launching it' {
            Mock Get-Command { return [PSCustomObject]@{ Name = 'Get-AppxPackage' } } -ParameterFilter {
                $Name -eq 'Get-AppxPackage'
            }
            Mock Get-AppxPackage {
                param($Name)
                if ($Name -eq 'AgileBits.1Password') {
                    return [PSCustomObject]@{
                        PackageFamilyName = 'Agilebits.1Password_amwd9z03whsfe'
                        Version           = [version]'8.12.36.40'
                        InstallLocation   = 'C:\Apps\1Password'
                    }
                }
                return $null
            }
            Mock Get-ChildItem {
                return [PSCustomObject]@{ VersionInfo = [PSCustomObject]@{ ProductVersion = '8.12.36.40' } }
            } -ParameterFilter { $Path -eq 'C:\Apps\1Password\1Password.exe' }

            $verified = $handler.TestPackageVerification([PSCustomObject]@{
                    command     = 'AgileBits.1Password'
                    type        = 'windowsInstalledProduct'
                    appxPackage = [PSCustomObject]@{
                        name              = 'AgileBits.1Password'
                        packageFamilyName = 'Agilebits.1Password_amwd9z03whsfe'
                        executable        = '1Password.exe'
                    }
                })

            $verified | Should -BeTrue
            Should -Invoke Get-AppxPackage -Times 1 -ParameterFilter { $Name -eq 'AgileBits.1Password' }
        }

        It 'should verify an MSI application from an exact uninstall product code and installed version' {
            $registryKey = [PSCustomObject]@{
                Name   = '{BD400747-F0C1-5638-A859-982036102EDF}'
                PSPath = 'Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Uninstall\{BD400747-F0C1-5638-A859-982036102EDF}'
            }
            Mock Get-AppxPackage { return $null }
            Mock Get-ChildItem { return @($registryKey) } -ParameterFilter {
                $LiteralPath -like '*\Uninstall'
            }
            Mock Get-ItemProperty {
                return [PSCustomObject]@{ DisplayVersion = '1.13.7'; DisplayName = 'Obsidian'; Publisher = 'Dynalist Inc.' }
            } -ParameterFilter {
                $LiteralPath -eq $registryKey.PSPath
            }
            Mock Get-ChildItem {
                return [PSCustomObject]@{ VersionInfo = [PSCustomObject]@{ ProductVersion = '1.13.7' } }
            } -ParameterFilter { $Path -eq 'C:\Apps\Obsidian.exe' }

            $verified = $handler.TestPackageVerification([PSCustomObject]@{
                    command        = 'Obsidian'
                    type           = 'windowsInstalledProduct'
                    uninstallEntry = [PSCustomObject]@{
                        productCodes    = @('{bd400747-f0c1-5638-a859-982036102edf}')
                        displayName     = 'Obsidian'
                        publisher       = 'Dynalist Inc.'
                        executablePaths = @('C:\Apps\Obsidian.exe')
                    }
                })

            $verified | Should -BeTrue
            Should -Invoke Get-ItemProperty -Times 1
        }

        It 'should verify PowerToys when WinGet uses its preview ARP display name' {
            $env:LOCALAPPDATA = 'C:\Users\test\AppData\Local'
            $wingetManifestPath = Join-Path $PSScriptRoot '../../../../windows/winget/packages.json'
            $wingetManifest = Get-Content -LiteralPath $wingetManifestPath -Raw | ConvertFrom-Json
            $wingetSource = @($wingetManifest.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' }) | Select-Object -First 1
            $package = @($wingetSource.Packages | Where-Object PackageIdentifier -EQ 'Microsoft.PowerToys') | Select-Object -First 1
            $verifyCommand = $package.verifyCommand
            $verifyCommand.uninstallEntry.displayNamePattern | Should -Be '^PowerToys(?: \(Preview\))?$'
            'Microsoft PowerToys Preview' | Should -Not -Match $verifyCommand.uninstallEntry.displayNamePattern
            $registryKey = [PSCustomObject]@{
                Name   = 'PowerToys'
                PSPath = 'Microsoft.PowerShell.Core\Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall\PowerToys'
            }
            Mock Get-AppxPackage { return $null }
            Mock Get-ChildItem { return @($registryKey) } -ParameterFilter {
                $LiteralPath -like '*\Uninstall'
            }
            Mock Get-ItemProperty {
                return [PSCustomObject]@{
                    DisplayName = 'PowerToys (Preview)'
                    Publisher   = 'Microsoft Corporation'
                }
            } -ParameterFilter { $LiteralPath -eq $registryKey.PSPath }
            Mock Get-ChildItem {
                return [PSCustomObject]@{ VersionInfo = [PSCustomObject]@{ ProductVersion = '0.101.2362.0' } }
            } -ParameterFilter { $Path -eq 'C:\Users\test\AppData\Local\PowerToys\PowerToys.exe' }

            $verified = $handler.TestPackageVerification($verifyCommand)

            $verified | Should -BeTrue
            Should -Invoke Get-ChildItem -Times 1 -ParameterFilter {
                $Path -eq 'C:\Users\test\AppData\Local\PowerToys\PowerToys.exe'
            }
        }

        It 'should verify a product code found in a single matching uninstall string' {
            $registryKey = [PSCustomObject]@{
                Name   = 'DiscordSetup'
                PSPath = 'Microsoft.PowerShell.Core\Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall\DiscordSetup'
            }
            Mock Get-AppxPackage { return $null }
            Mock Get-ChildItem { return @($registryKey) } -ParameterFilter {
                $LiteralPath -like '*\Uninstall'
            }
            Mock Get-ItemProperty {
                return [PSCustomObject]@{
                    DisplayVersion  = '1.0.0'
                    DisplayName     = 'Discord'
                    Publisher       = 'Discord Inc.'
                    UninstallString = 'C:\Apps\Discord\Update.exe --uninstall'
                }
            } -ParameterFilter {
                $LiteralPath -eq $registryKey.PSPath
            }
            Mock Get-ChildItem {
                return [PSCustomObject]@{ VersionInfo = [PSCustomObject]@{ ProductVersion = '1.0.0' } }
            } -ParameterFilter { $Path -eq 'C:\Apps\Discord.exe' }

            $verified = $handler.TestPackageVerification([PSCustomObject]@{
                    command        = 'Discord'
                    type           = 'windowsInstalledProduct'
                    uninstallEntry = [PSCustomObject]@{
                        productCodes    = @('Discord')
                        displayName     = 'Discord'
                        publisher       = 'Discord Inc.'
                        executablePaths = @('C:\Apps\Discord.exe')
                    }
                })

            $verified | Should -BeTrue
        }

        It 'should verify Orca from its actual per-user uninstall name and DisplayIcon executable' {
            $orcaExecutable = Join-Path $env:LOCALAPPDATA 'Programs\orca\Orca.exe'
            $registryKey = [PSCustomObject]@{
                Name   = '{2B325EC9-0ED1-575F-AD70-E08307AEE879}'
                PSPath = 'Microsoft.PowerShell.Core\Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall\{2B325EC9-0ED1-575F-AD70-E08307AEE879}'
            }
            Mock Get-AppxPackage { return $null }
            Mock Get-ChildItem { return @($registryKey) } -ParameterFilter {
                $LiteralPath -like '*\Uninstall'
            }
            Mock Get-ItemProperty {
                return [PSCustomObject]@{
                    DisplayVersion = '1.4.205'
                    DisplayName    = 'Orca'
                    Publisher      = 'Stably AI'
                    DisplayIcon    = "$orcaExecutable,0"
                }
            } -ParameterFilter { $LiteralPath -eq $registryKey.PSPath }
            Mock Get-ChildItem {
                return [PSCustomObject]@{ VersionInfo = [PSCustomObject]@{ ProductVersion = '1.4.205.0' } }
            } -ParameterFilter { $Path -eq $orcaExecutable }

            $verified = $handler.TestPackageVerification([PSCustomObject]@{
                    command        = 'OrcaSlicer'
                    type           = 'windowsInstalledProduct'
                    uninstallEntry = [PSCustomObject]@{
                        productCodes = @('2b325ec9-0ed1-575f-ad70-e08307aee879')
                        displayName  = 'Orca'
                    }
                })

            $verified | Should -BeTrue
        }

        It 'should check a single manifest executable path and DisplayIcon as separate candidates' {
            $manifestExecutable = 'C:\Apps\VC_redist.x64.exe'
            $displayIconExecutable = 'C:\Windows\System32\vcruntime140.exe'
            $registryKey = [PSCustomObject]@{
                Name   = 'VC_redist.x64'
                PSPath = 'Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Uninstall\VC_redist.x64'
            }
            Mock Get-AppxPackage { return $null }
            Mock Get-ChildItem { return @($registryKey) } -ParameterFilter {
                $LiteralPath -like '*\Uninstall'
            }
            Mock Get-ItemProperty {
                return [PSCustomObject]@{
                    DisplayName = 'Microsoft Visual C++ 2015-2022 Redistributable (x64)'
                    Publisher   = 'Microsoft Corporation'
                    DisplayIcon = "$displayIconExecutable,0"
                }
            } -ParameterFilter { $LiteralPath -eq $registryKey.PSPath }
            Mock Get-ChildItem { }
            Mock Get-ChildItem {
                return [PSCustomObject]@{ VersionInfo = [PSCustomObject]@{ ProductVersion = '14.40.33810.0' } }
            } -ParameterFilter { $Path -eq $displayIconExecutable }

            $verified = $handler.TestPackageVerification([PSCustomObject]@{
                    command        = 'Microsoft.VCRedist.2015+.x64'
                    type           = 'windowsInstalledProduct'
                    uninstallEntry = [PSCustomObject]@{
                        displayName     = 'Microsoft Visual C++ 2015-2022 Redistributable (x64)'
                        publisher       = 'Microsoft Corporation'
                        executablePaths = @($manifestExecutable)
                    }
                })

            $verified | Should -BeTrue
            Should -Invoke Get-ChildItem -Times 1 -ParameterFilter { $Path -eq $manifestExecutable }
            Should -Invoke Get-ChildItem -Times 1 -ParameterFilter { $Path -eq $displayIconExecutable }
        }

        It 'should reject an uninstall registration with no valid installed version' {
            $registryKey = [PSCustomObject]@{
                Name   = 'Discord'
                PSPath = 'Microsoft.PowerShell.Core\Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall\Discord'
            }
            Mock Get-AppxPackage { return $null }
            Mock Get-ChildItem { return @($registryKey) } -ParameterFilter {
                $LiteralPath -like '*\Uninstall'
            }
            Mock Get-ItemProperty {
                return [PSCustomObject]@{ DisplayVersion = 'unknown'; DisplayName = 'Discord'; Publisher = 'Discord Inc.' }
            } -ParameterFilter {
                $LiteralPath -eq $registryKey.PSPath
            }

            $verified = $handler.TestPackageVerification([PSCustomObject]@{
                    command        = 'Discord'
                    type           = 'windowsInstalledProduct'
                    uninstallEntry = [PSCustomObject]@{
                        productCodes    = @('Discord')
                        displayName     = 'Discord'
                        publisher       = 'Discord Inc.'
                        executablePaths = @('C:\Apps\Discord.exe')
                    }
                })

            $verified | Should -BeFalse
        }

        It 'should require an installed Visual Studio Build Tools instance and the configured compiler component' {
            Mock Get-Command { return [PSCustomObject]@{ Source = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe' } } -ParameterFilter {
                $Name -eq 'vswhere.exe'
            }
            Mock Test-Path { return $true } -ParameterFilter {
                $LiteralPath -like '*\\VC\\Tools\\MSVC\\*\\bin\\Hostx64\\x64\\cl.exe'
            }
            Mock Get-ChildItem {
                return [PSCustomObject]@{ VersionInfo = [PSCustomObject]@{ ProductVersion = '19.44.35222' } }
            } -ParameterFilter {
                $Path -like '*VC\Tools\MSVC*\bin\Hostx64\x64\cl.exe'
            }
            Mock Invoke-VerifyCommand {
                $global:LASTEXITCODE = 0
                return '[{"installationVersion":"17.14.41","installationPath":"C:\\BuildTools"}]'
            } -ParameterFilter {
                $Command -like '*vswhere.exe'
            }

            $verified = $handler.TestPackageVerification([PSCustomObject]@{
                    command              = 'Microsoft.VisualStudio.Product.BuildTools'
                    type                 = 'visualStudioInstanceVersion'
                    productId            = 'Microsoft.VisualStudio.Product.BuildTools'
                    minimumVersion       = '17.0'
                    requiredComponent    = 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64'
                    compilerRelativePath = 'VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe'
                })

            $verified | Should -BeTrue
            Should -Invoke Invoke-VerifyCommand -Times 1 -ParameterFilter {
                $Arguments -contains '-requires' -and $Arguments -contains 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64'
            }
        }

        It 'should reject an older Visual Studio Build Tools instance even when the C++ compiler exists' {
            Mock Get-Command { return [PSCustomObject]@{ Source = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe' } } -ParameterFilter {
                $Name -eq 'vswhere.exe'
            }
            Mock Get-ChildItem {
                return [PSCustomObject]@{ VersionInfo = [PSCustomObject]@{ ProductVersion = '19.44.35222' } }
            } -ParameterFilter { $Path -like '*VC\Tools\MSVC*\bin\Hostx64\x64\cl.exe' }
            Mock Invoke-VerifyCommand {
                $global:LASTEXITCODE = 0
                return '[{"installationVersion":"16.11.35","installationPath":"C:\\BuildTools"}]'
            } -ParameterFilter { $Command -like '*vswhere.exe' }

            $verified = $handler.TestPackageVerification([PSCustomObject]@{
                    command              = 'Microsoft.VisualStudio.Product.BuildTools'
                    type                 = 'visualStudioInstanceVersion'
                    productId            = 'Microsoft.VisualStudio.Product.BuildTools'
                    minimumVersion       = '17.0'
                    requiredComponent    = 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64'
                    compilerRelativePath = 'VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe'
                })

            $verified | Should -BeFalse
        }
    }

    Context 'WinGet timeout diagnostics' {
        It 'should classify a locked stale cache and redact local user paths' {
            $logDir = Join-Path $TestDrive 'winget-logs'
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            $env:DOTFILES_WINGET_DIAGNOSTIC_LOG_DIR = $logDir
            try {
                $logPath = Join-Path $logDir 'WinGet-test.log'
                [System.IO.File]::WriteAllText($logPath, @'
2026-09-23 [CLI ] Found one app. App id: hadolint.hadolint
2026-09-23 [CLI ] Hash does not match. Removing existing installer file C:\Users\private\AppData\Local\Temp\hadolint.exe
2026-09-23 [W] Failed to remove installer file. Reason: The process cannot access the file because it is being used by another process.
2026-09-23 [CORE] DeliveryOptimization downloading from url: https://example.invalid/file.exe?token=secret
'@)

                $diagnosis = $handler.GetWingetTimeoutDiagnosis('hadolint.hadolint', [DateTime]::UtcNow.AddMinutes(-1))

                $diagnosis | Should -Match 'class=installer-cache-contention'
                $diagnosis | Should -Match 'confidence=medium'
                $diagnosis | Should -Match 'another process'
                $diagnosis | Should -Not -Match 'C:\\Users\\private'
                $diagnosis | Should -Not -Match 'token=secret'
            }
            finally {
                Remove-Item Env:\DOTFILES_WINGET_DIAGNOSTIC_LOG_DIR -ErrorAction SilentlyContinue
            }
        }

        It 'should report an unknown diagnosis if no matching package log exists' {
            $logDir = Join-Path $TestDrive 'empty-winget-logs'
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            $env:DOTFILES_WINGET_DIAGNOSTIC_LOG_DIR = $logDir
            try {
                $diagnosis = $handler.GetWingetTimeoutDiagnosis('unknown.package', [DateTime]::UtcNow.AddMinutes(-1))
                $diagnosis | Should -Match 'class=unknown confidence=low'
            }
            finally {
                Remove-Item Env:\DOTFILES_WINGET_DIAGNOSTIC_LOG_DIR -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Constructor' {
        It 'should set <property> correctly' -ForEach @(
            @{ property = "Name"; expected = "Winget"; checkType = "Be" }
            @{ property = "Description"; expected = $null; checkType = "Not -BeNullOrEmpty" }
            @{ property = "Order"; expected = 5; checkType = "Be" }
            @{ property = "RequiresAdmin"; expected = $false; checkType = "Be" }
        ) {
            if ($checkType -eq "Be") {
                $handler.$property | Should -Be $expected
            }
            else {
                $handler.$property | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'CanApply - winget not found' {
        BeforeEach {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExist { return $true }
            Mock Invoke-Winget { $global:LASTEXITCODE = 0; return "v1.6.0" }
        }

        It 'should return false' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $false
        }
    }

    Context 'CanApply - import mode without package file' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Invoke-Winget { $global:LASTEXITCODE = 0; return "v1.6.0" }
            Mock Test-PathExist { return $false }
        }

        It 'should return false' {
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.CanApply($ctx)
            $result | Should -Be $false
        }
    }

    Context 'CanApply - import mode with all conditions met' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Invoke-Winget { $global:LASTEXITCODE = 0; return "v1.6.0" }
            Mock Test-PathExist { return $true }
        }

        It 'should return true' {
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.CanApply($ctx)
            $result | Should -Be $true
        }
    }

    Context 'CanApply - export mode with winget available' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Invoke-Winget { $global:LASTEXITCODE = 0; return "v1.6.0" }
        }

        It 'should return true even without package file' {
            $ctx.Options["WingetMode"] = "export"
            $result = $handler.CanApply($ctx)
            $result | Should -Be $true
        }
    }

    Context 'Apply - import mode: all packages not installed' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "winget" }
                            Packages      = @(
                                [PSCustomObject]@{ PackageIdentifier = "Git.Git"; verifyCommand = [PSCustomObject]@{ command = "git"; args = @("--version") } },
                                [PSCustomObject]@{ PackageIdentifier = "twpayne.chezmoi"; verifyCommand = [PSCustomObject]@{ command = "chezmoi"; args = @("--version") } }
                            )
                        }
                    )
                }
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "list") {
                    $global:LASTEXITCODE = 1
                }
                else {
                    $global:LASTEXITCODE = 0
                }
            }
            Mock Invoke-VerifyCommand {
                $global:LASTEXITCODE = 0
                return "1.0.0"
            }
            Mock Test-Path { return $false } -ParameterFilter { $Path -like "*\.cargo\bin" }
        }

        It 'should return success result' {
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "インストール"
        }

        It 'should call winget install for each package' {
            $script:installIds = @()
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "list") {
                    $global:LASTEXITCODE = 1
                }
                elseif ($Arguments -contains "install") {
                    $idIndex = [array]::IndexOf($Arguments, "--id") + 1
                    if ($idIndex -gt 0 -and $idIndex -lt $Arguments.Count) {
                        $script:installIds += $Arguments[$idIndex]
                    }
                    $global:LASTEXITCODE = 0
                }
            }
            $ctx.Options["WingetMode"] = "import"
            $handler.Apply($ctx)
            $script:installIds | Should -Contain "Git.Git"
            $script:installIds | Should -Contain "twpayne.chezmoi"
        }

        It 'should constrain winget packages to the winget source' {
            $script:capturedInstallArgs = $null
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "list") {
                    $global:LASTEXITCODE = 1
                }
                elseif ($Arguments -contains "install") {
                    $script:capturedInstallArgs = $Arguments
                    $global:LASTEXITCODE = 0
                }
            }

            $ctx.Options["WingetMode"] = "import"
            $handler.Apply($ctx)

            $script:capturedInstallArgs | Should -Contain "--source"
            $script:capturedInstallArgs | Should -Contain "winget"
        }

        It 'should refresh process PATH after successful installs before verification' {
            $ctx.Options["WingetMode"] = "import"

            $handler.Apply($ctx)

            Should -Invoke Update-ProcessEnvironmentPath -Times 2
            Should -Invoke Invoke-VerifyCommand -Times 2
        }
    }

    Context 'Apply - import mode: all packages already installed' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "winget" }
                            Packages      = @(
                                [PSCustomObject]@{ PackageIdentifier = "Git.Git" }
                            )
                        }
                    )
                }
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "list" -and $Arguments -notcontains "--id") {
                    # GetInstalledPackageIds 用: winget list の出力を模倣
                    $global:LASTEXITCODE = 0
                    return @(
                        "Name          Id         Version  Source",
                        "-------------------------------------------",
                        "Git           Git.Git    2.43.0   winget"
                    )
                }
                $global:LASTEXITCODE = 0
            }
            Mock Test-Path { return $false } -ParameterFilter { $Path -like "*\.cargo\bin" }
        }

        It 'should run winget install for installed packages to pick up the latest installer' {
            $script:installCalled = $false
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "install") {
                    $script:installCalled = $true
                }
                if ($Arguments -contains "list" -and $Arguments -notcontains "--id") {
                    $global:LASTEXITCODE = 0
                    return @(
                        "Name          Id         Version  Source",
                        "-------------------------------------------",
                        "Git           Git.Git    2.43.0   winget"
                    )
                }
                $global:LASTEXITCODE = 0
            }
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "1 個インストール"
            $script:installCalled | Should -Be $true
        }

        It 'should match the manifest ID when a dotted package version appears before it in winget output' {
            $script:individualListCalls = 0
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = 'winget' }
                            Packages      = @(
                                [PSCustomObject]@{ PackageIdentifier = 'Contoso.Tool' }
                            )
                        }
                    )
                }
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains 'list' -and $Arguments -notcontains '--id') {
                    $global:LASTEXITCODE = 0
                    return @(
                        'Name            Id             Version  Source',
                        '------------------------------------------------',
                        'Product.Name    Contoso.Tool   2.43.0   winget'
                    )
                }
                if ($Arguments -contains 'list' -and $Arguments -contains '--id') {
                    $script:individualListCalls++
                    $global:LASTEXITCODE = 1
                    return @('No package found')
                }
                $global:LASTEXITCODE = 1
                return @('No applicable update found')
            }

            $ctx.Options['WingetMode'] = 'import'
            $result = $handler.Apply($ctx)

            $result.Success | Should -BeTrue
            $script:individualListCalls | Should -Be 0
        }

        It 'should count a package once when pre-install verification passes before an update' {
            $script:verifyCalls = 0
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "winget" }
                            Packages      = @(
                                [PSCustomObject]@{
                                    PackageIdentifier = "Git.Git"
                                    verifyCommand     = [PSCustomObject]@{ command = "git"; args = @("--version") }
                                }
                            )
                        }
                    )
                }
            }
            Mock Invoke-VerifyCommand {
                $script:verifyCalls++
                $global:LASTEXITCODE = 0
                return "git version 2.43.0"
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "list" -and $Arguments -notcontains "--id") {
                    $global:LASTEXITCODE = 0
                    return @(
                        "Name          Id         Version  Source",
                        "-------------------------------------------",
                        "Git           Git.Git    2.43.0   winget"
                    )
                }
                $global:LASTEXITCODE = 0
                return "installed"
            }

            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -BeTrue
            $result.Message | Should -Match "1 個インストール"
            $result.Message | Should -Not -Match "1 個検証済み"
            $script:verifyCalls | Should -Be 2
        }

        It 'should treat already-latest no-op installs without verifyCommand as success' {
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "install") {
                    $global:LASTEXITCODE = 1
                    return @("No applicable update found")
                }
                if ($Arguments -contains "list" -and $Arguments -notcontains "--id") {
                    $global:LASTEXITCODE = 0
                    return @(
                        "Name          Id         Version  Source",
                        "-------------------------------------------",
                        "Git           Git.Git    2.43.0   winget"
                    )
                }
                $global:LASTEXITCODE = 0
            }

            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "1 個変更なし"
        }

        It 'should treat localized already-latest no-op installs without verifyCommand as success' {
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "install") {
                    $global:LASTEXITCODE = 1
                    return @(
                        "既存のパッケージが既にインストールされています。インストールされているパッケージ...をアップグレードしようとしています",
                        "利用可能なアップグレードが見つかりませんでした。",
                        "構成されたソースから入手できる新しいパッケージ バージョンはありません。"
                    )
                }
                if ($Arguments -contains "list" -and $Arguments -notcontains "--id") {
                    $global:LASTEXITCODE = 0
                    return @(
                        "Name          Id         Version  Source",
                        "-------------------------------------------",
                        "Git           Git.Git    2.43.0   winget"
                    )
                }
                $global:LASTEXITCODE = 0
            }

            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "1 個変更なし"
        }

        It 'should not classify a no-op phrase as unchanged when pre-install inventory did not find the package' {
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains 'list' -and $Arguments -notcontains '--id') {
                    $global:LASTEXITCODE = 0
                    return @('Name Id Version Source', '-------------------')
                }
                if ($Arguments -contains 'list' -and $Arguments -contains '--id') {
                    $global:LASTEXITCODE = 1
                    return @('No package found')
                }
                if ($Arguments -contains 'install') {
                    $global:LASTEXITCODE = 1
                    return @('No applicable update found', 'Installer failed with exit code: 1603')
                }
                $global:LASTEXITCODE = 0
                return @()
            }

            $ctx.Options['WingetMode'] = 'import'
            $result = $handler.Apply($ctx)

            $result.Success | Should -BeFalse
            $result.Message | Should -Match '1 個失敗'
            $result.Message | Should -Not -Match '変更なし'
        }
    }

    Context 'Apply - import mode: installed package verification fails' {
        BeforeEach {
            $script:verifyCalls = 0
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "winget" }
                            Packages      = @(
                                [PSCustomObject]@{
                                    PackageIdentifier = "twpayne.chezmoi"
                                    verifyCommand     = [PSCustomObject]@{ command = "chezmoi"; args = @("--version") }
                                }
                            )
                        }
                    )
                }
            }
            Mock Invoke-VerifyCommand {
                if (-not $script:verifyCalls) { $script:verifyCalls = 0 }
                $script:verifyCalls++
                if ($script:verifyCalls -eq 1) {
                    $global:LASTEXITCODE = 1
                    throw "chezmoi not found"
                }
                $global:LASTEXITCODE = 0
                return "2.70.5"
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "list" -and $Arguments -notcontains "--id") {
                    $global:LASTEXITCODE = 0
                    return @(
                        "Name     Id              Version Source",
                        "----------------------------------------",
                        "chezmoi  twpayne.chezmoi 2.70.5  winget"
                    )
                }
                $global:LASTEXITCODE = 0
            }
            Mock Test-Path { return $false } -ParameterFilter { $Path -like "*\.cargo\bin" }
        }

        It 'should reinstall with force when installed package verification fails' {
            $script:installArgs = $null
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "list" -and $Arguments -notcontains "--id") {
                    $global:LASTEXITCODE = 0
                    return @(
                        "Name     Id              Version Source",
                        "----------------------------------------",
                        "chezmoi  twpayne.chezmoi 2.70.5  winget"
                    )
                }
                if ($Arguments -contains "install") {
                    $script:installArgs = $Arguments
                }
                $global:LASTEXITCODE = 0
            }

            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $script:installArgs | Should -Contain "--force"
            Should -Invoke Invoke-VerifyCommand -Times 2
        }
    }

    Context 'Apply - import mode: partial failure' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "winget" }
                            Packages      = @(
                                [PSCustomObject]@{ PackageIdentifier = "Fail.Package" }
                            )
                        }
                    )
                }
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "list") {
                    $global:LASTEXITCODE = 1
                }
                else {
                    $global:LASTEXITCODE = 1
                }
            }
            Mock Test-Path { return $false } -ParameterFilter { $Path -like "*\.cargo\bin" }
        }

        It 'should return failure with partial failure warning' {
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $false
            $result.Message | Should -Match "1 個失敗"
        }

        It 'should stream winget install output to the CLI when install fails' {
            Mock Write-Host { }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "list") {
                    $global:LASTEXITCODE = 1
                    return @()
                }
                if ($Arguments -contains "install") {
                    $global:LASTEXITCODE = 1
                    return @(
                        "Found Fail.Package",
                        "Installer failed with exit code: 1603"
                    )
                }
            }

            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            Should -Invoke Write-Host -ParameterFilter {
                [string]$Object -match 'Installer failed with exit code: 1603'
            }
        }
    }

    Context 'Apply - import mode: msstore package' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "msstore" }
                            Packages      = @(
                                [PSCustomObject]@{ PackageIdentifier = "Contoso.StoreApp" }
                            )
                        }
                    )
                }
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "list") {
                    $global:LASTEXITCODE = 1
                }
                else {
                    $global:LASTEXITCODE = 0
                }
            }
            Mock Test-Path { return $false } -ParameterFilter { $Path -like "*\.cargo\bin" }
        }

        It 'should pass --source msstore for msstore packages' {
            $script:capturedArgs = $null
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "install") {
                    $script:capturedArgs = $Arguments
                }
                if ($Arguments -contains "list") {
                    $global:LASTEXITCODE = 1
                }
                else {
                    $global:LASTEXITCODE = 0
                }
            }
            $ctx.Options["WingetMode"] = "import"
            $handler.Apply($ctx)
            $script:capturedArgs | Should -Contain "--source"
            $script:capturedArgs | Should -Contain "msstore"
        }
    }

    Context 'Apply - import mode: Codex Desktop msstore package' {
        BeforeEach {
            $script:codexInstallLocation = Join-Path $TestDrive "CodexDesktop"
            New-Item -ItemType Directory -Path $script:codexInstallLocation -Force | Out-Null
            @'
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10">
  <Applications>
    <Application Id="App" Executable="app\Codex.exe" EntryPoint="Windows.FullTrustApplication" />
  </Applications>
</Package>
'@ | Set-Content -LiteralPath (Join-Path $script:codexInstallLocation "AppxManifest.xml") -Encoding utf8
            New-Item -ItemType Directory -Path (Join-Path $script:codexInstallLocation "app") -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $script:codexInstallLocation "app\Codex.exe") -Force | Out-Null

            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "msstore" }
                            Packages      = @(
                                [PSCustomObject]@{
                                    PackageIdentifier = "9PLM9XGG6VKS"
                                    verifyCommand     = [PSCustomObject]@{
                                        type    = "appxLaunchTarget"
                                        command = "OpenAI.Codex"
                                        args    = @("OpenAI.Codex_2p2nqsd0c76g0!App")
                                    }
                                }
                            )
                        }
                    )
                }
            }
            Mock Get-Command { return [PSCustomObject]@{ Name = "Get-AppxPackage" } } -ParameterFilter {
                $Name -eq "Get-AppxPackage"
            }
            $script:getAppxPackageCalls = 0
            Mock Get-AppxPackage {
                param($Name)
                if ($Name -ne "OpenAI.Codex") {
                    return $null
                }
                $script:getAppxPackageCalls++
                return [PSCustomObject]@{
                    Name              = "OpenAI.Codex"
                    PackageFamilyName = "OpenAI.Codex_2p2nqsd0c76g0"
                    Version           = [version]"1.0.0.0"
                    InstallLocation   = $script:codexInstallLocation
                }
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "install") {
                    $script:capturedArgs = $Arguments
                    $global:LASTEXITCODE = 0
                    return "Installed Codex Desktop"
                }
                $global:LASTEXITCODE = 1
                return @()
            }
            Mock Test-Path { return $false } -ParameterFilter { $Path -like "*\.cargo\bin" }
        }

        It 'should install Codex Desktop from msstore and verify its AppX launch target' {
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "1 個インストール"
            $script:capturedArgs | Should -Contain "--id"
            $script:capturedArgs | Should -Contain "9PLM9XGG6VKS"
            $script:capturedArgs | Should -Contain "--source"
            $script:capturedArgs | Should -Contain "msstore"
            $script:getAppxPackageCalls | Should -Be 1
            Should -Invoke Get-AppxPackage -Times 1 -ParameterFilter {
                $Name -eq "OpenAI.Codex"
            }
        }
    }

    Context 'Apply - import mode: msstore package already installed' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "msstore" }
                            Packages      = @(
                                [PSCustomObject]@{ PackageIdentifier = "Contoso.StoreApp" }
                            )
                        }
                    )
                }
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "list" -and $Arguments -notcontains "--id") {
                    $global:LASTEXITCODE = 0
                    return @(
                        "Name              Id            Version  Source",
                        "-------------------------------------------------",
                        "Contoso Store App  Contoso.StoreApp  1.19.0   msstore"
                    )
                }
                $global:LASTEXITCODE = 0
            }
            Mock Test-Path { return $false } -ParameterFilter { $Path -like "*\.cargo\bin" }
        }

        It 'should call winget install so Microsoft Store packages can upgrade to latest' {
            $script:installCalled = $false
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "install") {
                    $script:installCalled = $true
                }
                if ($Arguments -contains "list" -and $Arguments -notcontains "--id") {
                    $global:LASTEXITCODE = 0
                    return @(
                        "Name              Id            Version  Source",
                        "-------------------------------------------------",
                        "Contoso Store App  Contoso.StoreApp  1.19.0   msstore"
                    )
                }
                $global:LASTEXITCODE = 0
            }
            $ctx.Options["WingetMode"] = "import"
            $handler.Apply($ctx)
            $script:installCalled | Should -Be $true
        }
    }

    Context 'Apply - import mode: empty packages' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "winget" }
                            Packages      = @()
                        }
                    )
                }
            }
        }

        It 'should return success with empty message' {
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "空"
        }
    }

    Context 'Apply - import mode: IsPackageInstalled throws exception' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "winget" }
                            Packages      = @(
                                [PSCustomObject]@{ PackageIdentifier = "Error.Package" }
                            )
                        }
                    )
                }
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "list") {
                    throw "winget list failed"
                }
                $global:LASTEXITCODE = 0
            }
            Mock Test-Path { return $false } -ParameterFilter { $Path -like "*\.cargo\bin" }
        }

        It 'should report a detection failure instead of treating the package as absent' {
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $false
            $result.Message | Should -Match "winget list failed"
            Should -Invoke Invoke-Winget -Times 0 -ParameterFilter { $Arguments -contains "install" }
        }
    }

    Context 'Apply - export mode success' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
            Mock New-DirectorySafe { }
            Mock Invoke-Winget {
                $global:LASTEXITCODE = 0
                return "Packages exported"
            }
        }

        It 'should return success result' {
            $ctx.Options["WingetMode"] = "export"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "エクスポート"
        }

        It 'should call winget export' {
            $script:wingetCalled = $false
            $script:wingetArgs = $null
            Mock Invoke-Winget {
                param($Arguments)
                $script:wingetCalled = $true
                $script:wingetArgs = $Arguments
                $global:LASTEXITCODE = 0
            }

            $ctx.Options["WingetMode"] = "export"
            $handler.Apply($ctx)

            $script:wingetCalled | Should -Be $true
            $script:wingetArgs | Should -Contain "export"
        }
    }

    Context 'Apply - export mode without directory' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $false }
            Mock New-DirectorySafe { }
            Mock Invoke-Winget {
                $global:LASTEXITCODE = 0
                return "Packages exported"
            }
        }

        It 'should create directory' {
            $script:dirCreated = $false
            Mock New-DirectorySafe {
                $script:dirCreated = $true
            }

            $ctx.Options["WingetMode"] = "export"
            $handler.Apply($ctx)

            $script:dirCreated | Should -Be $true
        }
    }

    Context 'Apply - export mode partial failure' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
            Mock Invoke-Winget {
                $global:LASTEXITCODE = 1
                return "Some packages could not be exported"
            }
        }

        It 'should return success with partial exclusion warning' {
            $ctx.Options["WingetMode"] = "export"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "一部除外"
        }
    }

    Context 'Apply - unknown mode' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
        }

        It 'should return failure result' {
            $ctx.Options["WingetMode"] = "unknown"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $false
            $result.Message | Should -Match "不明なモード"
        }
    }

    Context 'EnsureCargoPath - .cargo\bin does not exist' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
            Mock Test-Path { return $false } -ParameterFilter { $Path -like "*\.cargo\bin" }
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "winget" }
                            Packages      = @(
                                [PSCustomObject]@{ PackageIdentifier = "Git.Git" }
                            )
                        }
                    )
                }
            }
            Mock Invoke-Winget {
                param($Arguments)
                $global:LASTEXITCODE = 0
            }
            Mock Set-UserEnvironmentPath { }
        }

        It 'should not modify PATH' {
            $ctx.Options["WingetMode"] = "import"
            $handler.Apply($ctx)
            Should -Invoke Set-UserEnvironmentPath -Times 0
        }
    }

    Context 'EnsureCargoPath - .cargo\bin exists but not in PATH' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "winget" }
                            Packages      = @(
                                [PSCustomObject]@{ PackageIdentifier = "Git.Git" }
                            )
                        }
                    )
                }
            }
            Mock Invoke-Winget {
                param($Arguments)
                $global:LASTEXITCODE = 0
            }
            Mock Test-Path { return $true } -ParameterFilter { $Path -like "*\.cargo\bin" }
            Mock Get-UserEnvironmentPath { return "C:\Windows;C:\other" }
            Mock Set-UserEnvironmentPath { }
        }

        It 'should add .cargo\bin to User PATH' {
            $ctx.Options["WingetMode"] = "import"
            $handler.Apply($ctx)
            Should -Invoke Set-UserEnvironmentPath -Times 1 -ParameterFilter {
                $Path -like "*\.cargo\bin*"
            }
        }
    }

    Context 'EnsureCargoPath - .cargo\bin already in PATH' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "winget" }
                            Packages      = @(
                                [PSCustomObject]@{ PackageIdentifier = "Git.Git" }
                            )
                        }
                    )
                }
            }
            Mock Invoke-Winget {
                param($Arguments)
                $global:LASTEXITCODE = 0
            }
            Mock Test-Path { return $true } -ParameterFilter { $Path -like "*\.cargo\bin" }
            $cargoBin = "$env:USERPROFILE\.cargo\bin"
            Mock Get-UserEnvironmentPath { return "C:\Windows;$cargoBin" }.GetNewClosure()
            Mock Set-UserEnvironmentPath { }
        }

        It 'should not modify PATH' {
            $ctx.Options["WingetMode"] = "import"
            $handler.Apply($ctx)
            Should -Invoke Set-UserEnvironmentPath -Times 0
        }
    }

    Context 'Apply - exception thrown' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent { throw "winget error" }
        }

        It 'should return failure result' {
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $false
            $result.Message | Should -Match "winget error"
        }
    }

    Context 'Apply - import mode: verifyCommand fails after install' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "winget" }
                            Packages      = @(
                                [PSCustomObject]@{
                                    PackageIdentifier = "Broken.Package"
                                    verifyCommand     = [PSCustomObject]@{ command = "broken-cmd"; args = @("--version") }
                                }
                            )
                        }
                    )
                }
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "list") { $global:LASTEXITCODE = 1 } else { $global:LASTEXITCODE = 0 }
            }
            Mock Invoke-VerifyCommand { $global:LASTEXITCODE = 1; throw "command failed" }
            Mock Test-Path { return $false } -ParameterFilter { $Path -like "*\.cargo\bin" }
        }

        It 'should return failure and report verify failed count' {
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $false
            $result.Message | Should -Match "1 個検証失敗"
            $result.Message | Should -Not -Match "1 個インストール"
        }
    }

    Context 'Apply - import mode: WingetVerifyCommandOnly option' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "winget" }
                            Packages      = @(
                                [PSCustomObject]@{ PackageIdentifier = "GUI.App" },
                                [PSCustomObject]@{
                                    PackageIdentifier = "CLI.Tool"
                                    verifyCommand     = [PSCustomObject]@{ command = "cli-tool"; args = @("--version") }
                                },
                                [PSCustomObject]@{
                                    PackageIdentifier = "Volatile.Nightly"
                                    ciSkipInstall     = $true
                                    verifyCommand     = [PSCustomObject]@{ command = "volatile"; args = @("--version") }
                                },
                                [PSCustomObject]@{
                                    PackageIdentifier = "Manual.Skip"
                                    skipInstall       = $true
                                    verifyCommand     = [PSCustomObject]@{ command = "manual-skip"; args = @("--version") }
                                }
                            )
                        }
                    )
                }
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "list") { $global:LASTEXITCODE = 1 } else { $global:LASTEXITCODE = 0 }
            }
            Mock Invoke-VerifyCommand {
                $global:LASTEXITCODE = 0
                return "1.0.0"
            }
            Mock Test-Path { return $false } -ParameterFilter { $Path -like "*\.cargo\bin" }
        }

        It 'should install only packages with verifyCommand' {
            $script:installIds = @()
            $handler._bufferLogs = $true
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "list") {
                    $global:LASTEXITCODE = 1
                }
                elseif ($Arguments -contains "install") {
                    $idIndex = [array]::IndexOf($Arguments, "--id") + 1
                    $script:installIds += $Arguments[$idIndex]
                    $global:LASTEXITCODE = 0
                }
            }

            $ctx.Options["WingetMode"] = "import"
            $ctx.Options["WingetVerifyCommandOnly"] = $true
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $script:installIds | Should -Contain "CLI.Tool"
            $script:installIds | Should -Not -Contain "GUI.App"
            $script:installIds | Should -Not -Contain "Volatile.Nightly"
            $script:installIds | Should -Not -Contain "Manual.Skip"
            @($handler._logBuffer | ForEach-Object { $_.Message } | Where-Object { $_ -like 'CI_VERIFICATION_INVENTORY:*' }) |
                Should -Be @('CI_VERIFICATION_INVENTORY: CLI.Tool')
        }

        It 'should skip install when an installed package verifyCommand already works' {
            Mock Invoke-VerifyCommand { $global:LASTEXITCODE = 0; return "1.0.0" }
            $script:installIds = @()
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "list" -and $Arguments -notcontains "--id") {
                    $global:LASTEXITCODE = 0
                    return @(
                        "Name       Id        Version Source",
                        "------------------------------------",
                        "CLI.Tool   CLI.Tool  1.0.0   winget"
                    )
                }
                elseif ($Arguments -contains "install") {
                    $idIndex = [array]::IndexOf($Arguments, "--id") + 1
                    $script:installIds += $Arguments[$idIndex]
                    $global:LASTEXITCODE = 0
                }
            }

            $ctx.Options["WingetMode"] = "import"
            $ctx.Options["WingetVerifyCommandOnly"] = $true
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "検証済み"
            $script:installIds.Count | Should -Be 0
        }
    }

    Context 'Apply - import mode: package installArgs' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "winget" }
                            Packages      = @(
                                [PSCustomObject]@{
                                    PackageIdentifier = "Microsoft.PowerShell"
                                    installArgs       = @("--installer-type", "wix")
                                    verifyCommand     = [PSCustomObject]@{ command = "pwsh"; args = @("--version") }
                                }
                            )
                        }
                    )
                }
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "list") { $global:LASTEXITCODE = 1 } else { $global:LASTEXITCODE = 0 }
            }
            Mock Invoke-VerifyCommand {
                $global:LASTEXITCODE = 0
                return "PowerShell 7.6.2"
            }
            Mock Test-Path { return $false } -ParameterFilter { $Path -like "*\.cargo\bin" }
        }

        It 'should pass extra install arguments to winget install' {
            $script:capturedArgs = $null
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "install") {
                    $script:capturedArgs = $Arguments
                }
                if ($Arguments -contains "list") { $global:LASTEXITCODE = 1 } else { $global:LASTEXITCODE = 0 }
            }

            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $script:capturedArgs | Should -Contain "--installer-type"
            $script:capturedArgs | Should -Contain "wix"
        }

        It 'should ignore package Version metadata so winget selects the latest installer' {
            $script:capturedArgs = $null
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "winget" }
                            Packages      = @(
                                [PSCustomObject]@{
                                    PackageIdentifier = "Versioned.Tool"
                                    Version           = "1.2.3"
                                }
                            )
                        }
                    )
                }
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "install") {
                    $script:capturedArgs = $Arguments
                }
                if ($Arguments -contains "list") { $global:LASTEXITCODE = 1 } else { $global:LASTEXITCODE = 0 }
            }

            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $script:capturedArgs | Should -Not -Contain "--version"
            $script:capturedArgs | Should -Not -Contain "1.2.3"
        }
    }

    Context 'Apply - import mode: package installTimeoutSeconds' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
            Mock Test-Path { return $false } -ParameterFilter { $Path -like "*\.cargo\bin" }
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "winget" }
                            Packages      = @(
                                [PSCustomObject]@{
                                    PackageIdentifier     = "Google.CloudSDK"
                                    installTimeoutSeconds = 900
                                    pathEntries           = @("%LOCALAPPDATA%\Google\Cloud SDK\google-cloud-sdk\bin")
                                    verifyCommand         = [PSCustomObject]@{ command = "gcloud"; args = @("version") }
                                }
                            )
                        }
                    )
                }
            }
            Mock Invoke-VerifyCommand {
                $global:LASTEXITCODE = 0
                return "Google Cloud SDK 1.2.3"
            }
            Mock Invoke-Winget {
                param($Arguments, $TimeoutSeconds)
                $null = $TimeoutSeconds
                if ($Arguments -contains "list") { $global:LASTEXITCODE = 1 } else { $global:LASTEXITCODE = 0 }
            }
        }

        It 'should pass package install timeout to winget install' {
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            Should -Invoke Invoke-Winget -Times 1 -ParameterFilter {
                $Arguments -contains "install" -and
                $Arguments -contains "Google.CloudSDK" -and
                $TimeoutSeconds -eq 900
            }
        }
    }

    Context 'Apply - import mode: package portableLink' {
        BeforeEach {
            $script:origLocalAppData = $env:LOCALAPPDATA
            $script:origUserProfile = $env:USERPROFILE
            $env:LOCALAPPDATA = Join-Path $TestDrive "LocalAppData"
            $env:USERPROFILE = Join-Path $TestDrive "UserProfile"
            $script:packageDir = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages\oxc-project.oxlint_Microsoft.Winget.Source"
            New-Item -ItemType Directory -Path $script:packageDir -Force | Out-Null
            Set-Content -Path (Join-Path $script:packageDir "oxlint-x86_64-pc-windows-msvc.exe") -Value "exe" -NoNewline

            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "winget" }
                            Packages      = @(
                                [PSCustomObject]@{
                                    PackageIdentifier = "oxc-project.oxlint"
                                    portableLink      = [PSCustomObject]@{
                                        linkName      = "oxlint.exe"
                                        targetPattern = "oxlint-*.exe"
                                    }
                                    verifyCommand     = [PSCustomObject]@{ command = "oxlint"; args = @("--version") }
                                }
                            )
                        }
                    )
                }
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "list") { $global:LASTEXITCODE = 1 } else { $global:LASTEXITCODE = 0 }
            }
            Mock Invoke-VerifyCommand { $global:LASTEXITCODE = 0; return "1.0.0" }
            Mock Get-UserEnvironmentPath { return "C:\Windows\System32" }
            Mock Set-UserEnvironmentPath { }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "Directory" }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "SymbolicLink" }
            Mock Copy-Item { }
        }
        AfterEach {
            $env:LOCALAPPDATA = $script:origLocalAppData
            $env:USERPROFILE = $script:origUserProfile
        }

        It 'should create command shim before verification' {
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            Should -Invoke New-Item -Times 1 -ParameterFilter { $ItemType -eq "SymbolicLink" }
            Should -Invoke New-Item -Times 0 -ParameterFilter { $ItemType -eq "HardLink" }
            Should -Invoke Copy-Item -Times 0
            Should -Invoke Invoke-VerifyCommand -Times 1
            Should -Invoke Set-UserEnvironmentPath -Times 1
        }

        It 'should use a user-scope copy fallback when symlink creation fails' {
            Mock New-Item { throw "Developer Mode is required" } -ParameterFilter { $ItemType -eq "SymbolicLink" }
            Mock Copy-Item { }

            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            Should -Invoke New-Item -Times 1 -ParameterFilter { $ItemType -eq "SymbolicLink" }
            Should -Invoke Copy-Item -Times 1 -ParameterFilter {
                $LiteralPath -like "*oxlint-x86_64-pc-windows-msvc.exe" -and
                $Destination -like "*Links\oxlint.exe"
            }
        }
    }

    Context 'Apply - import mode: package pathEntries' {
        BeforeEach {
            $script:origPath = $env:PATH
            $script:toolDir = Join-Path $TestDrive "ToolBin"
            New-Item -ItemType Directory -Path $script:toolDir -Force | Out-Null

            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "winget" }
                            Packages      = @(
                                [PSCustomObject]@{
                                    PackageIdentifier = "Path.Tool"
                                    pathEntries       = @($script:toolDir)
                                    verifyCommand     = [PSCustomObject]@{ command = "path-tool"; args = @("--version") }
                                }
                            )
                        }
                    )
                }
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "list") { $global:LASTEXITCODE = 1 } else { $global:LASTEXITCODE = 0 }
            }
            Mock Invoke-VerifyCommand { $global:LASTEXITCODE = 0; return "1.0.0" }
            Mock Get-UserEnvironmentPath { return "C:\Windows\System32" }
            Mock Set-UserEnvironmentPath { }
            Mock Test-Path { return $false } -ParameterFilter { $Path -like "*\.cargo\bin" }
        }
        AfterEach {
            $env:PATH = $script:origPath
        }

        It 'should add configured path entries before verification' {
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $env:PATH -split ";" | Should -Contain $script:toolDir
            Should -Invoke Invoke-VerifyCommand -Times 1
            Should -Invoke Set-UserEnvironmentPath -Times 1 -ParameterFilter {
                $Path -like "*$($script:toolDir)*"
            }
        }

        It 'should not warn when one of multiple path entry candidates exists' {
            $script:missingToolDir = Join-Path $TestDrive "MissingToolBin"
            Mock Write-Host { }
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "winget" }
                            Packages      = @(
                                [PSCustomObject]@{
                                    PackageIdentifier = "Path.Tool"
                                    pathEntries       = @($script:missingToolDir, $script:toolDir)
                                    verifyCommand     = [PSCustomObject]@{ command = "path-tool"; args = @("--version") }
                                }
                            )
                        }
                    )
                }
            }

            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $env:PATH -split ";" | Should -Contain $script:toolDir
            Should -Invoke Write-Host -Times 0 -ParameterFilter {
                [string]$Object -match 'pathEntries の.*見つかりません'
            }
        }

        It 'should warn once when no path entry candidate exists' {
            $script:missingToolDir = Join-Path $TestDrive "MissingToolBin"
            Mock Write-Host { }
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "winget" }
                            Packages      = @(
                                [PSCustomObject]@{
                                    PackageIdentifier = "Path.Tool"
                                    pathEntries       = @($script:missingToolDir)
                                    verifyCommand     = [PSCustomObject]@{ command = "path-tool"; args = @("--version") }
                                }
                            )
                        }
                    )
                }
            }

            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            Should -Invoke Write-Host -Times 1 -ParameterFilter {
                [string]$Object -match 'pathEntries の候補ディレクトリが見つかりません' -and
                [string]$Object -match 'Path.Tool'
            }
        }
    }

    Context 'Apply - import mode: Microsoft.WSL verification' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
            Mock Test-Path { return $false } -ParameterFilter { $Path -like "*\.cargo\bin" }
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "winget" }
                            Packages      = @(
                                [PSCustomObject]@{
                                    PackageIdentifier = "Microsoft.WSL"
                                    verifyCommand     = [PSCustomObject]@{
                                        command          = "wsl"
                                        args             = @("--version")
                                        timeoutSeconds   = 30
                                        recoveryStrategy = "wingetRepairThenReinstall"
                                    }
                                }
                            )
                        }
                    )
                }
            }
        }

        It 'should defer Microsoft.WSL verification to admin WSL install during normal install' {
            Mock Test-WslAvailable { return $false }
            Mock Invoke-VerifyCommand {
                throw "wsl --version should be skipped when WSL base install is deferred to admin phase"
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "install" -or $Arguments -contains "repair" -or $Arguments -contains "uninstall") {
                    throw "winget install, repair, and uninstall should be skipped when WSL is deferred to admin phase"
                }
                $global:LASTEXITCODE = 1
                return "入力条件に一致するインストール済みのパッケージが見つかりませんでした。"
            }

            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "1 個管理者フェーズ待ち"
            Should -Invoke Invoke-Winget -Times 0 -ParameterFilter { $Arguments -contains "install" }
            Should -Invoke Invoke-Winget -Times 0 -ParameterFilter { $Arguments -contains "repair" }
            Should -Invoke Invoke-Winget -Times 0 -ParameterFilter { $Arguments -contains "uninstall" }
            Should -Invoke Invoke-VerifyCommand -Times 0
        }

        It 'should defer Microsoft.WSL even when WSL is available during normal install' {
            Mock Test-WslAvailable { return $true }
            Mock Invoke-VerifyCommand {
                throw "wsl --version should be skipped in the non-admin winget phase"
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "install" -or $Arguments -contains "repair" -or $Arguments -contains "uninstall") {
                    throw "winget install, repair, and uninstall should be skipped when WSL is deferred to admin phase"
                }
                $global:LASTEXITCODE = 0
                return "Linux 用 Windows サブシステム Microsoft.WSL 2.7.3.0 winget"
            }

            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "1 個管理者フェーズ待ち"
            Should -Invoke Invoke-Winget -Times 0 -ParameterFilter { $Arguments -contains "install" }
            Should -Invoke Invoke-Winget -Times 0 -ParameterFilter { $Arguments -contains "repair" }
            Should -Invoke Invoke-Winget -Times 0 -ParameterFilter { $Arguments -contains "uninstall" }
            Should -Invoke Invoke-VerifyCommand -Times 0
        }

        It 'should keep Microsoft.WSL active during user-phase-only installs because no admin phase follows' {
            Mock Test-WslAvailable { return $false }
            Mock Invoke-VerifyCommand {
                $global:LASTEXITCODE = 0
                return "WSL version: 2.7.8.0"
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "install") {
                    $global:LASTEXITCODE = 0
                    return "インストールが完了しました"
                }
                if ($Arguments -contains "list" -and $Arguments -contains "--id") {
                    $global:LASTEXITCODE = 1
                    return "入力条件に一致するインストール済みのパッケージが見つかりませんでした。"
                }

                $global:LASTEXITCODE = 0
                return "Name Id Version Source"
            }

            $ctx.Options["WingetMode"] = "import"
            $ctx.Options["UserPhaseOnly"] = $true
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "1 個インストール"
            $result.Message | Should -Not -Match "管理者フェーズ待ち"
            Should -Invoke Invoke-Winget -Times 1 -ParameterFilter {
                $Arguments -contains "install" -and $Arguments -contains "Microsoft.WSL"
            }
            Should -Invoke Invoke-VerifyCommand -Times 1 -ParameterFilter {
                $Command -eq "wsl" -and
                $Arguments -contains "--version" -and
                $TimeoutSeconds -eq 30
            }
        }

        It 'should repair then reinstall installed Microsoft.WSL and fail when wsl --version still does not exit' {
            Mock Invoke-VerifyCommand {
                $global:LASTEXITCODE = 124
                return "検証コマンドがタイムアウトしました (30s): wsl --version"
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "install") {
                    $global:LASTEXITCODE = 0
                    return "インストールが完了しました"
                }
                if ($Arguments -contains "repair") {
                    $global:LASTEXITCODE = 0
                    return "修復が完了しました"
                }
                if ($Arguments -contains "uninstall") {
                    $global:LASTEXITCODE = 0
                    return "アンインストールが完了しました"
                }
                $global:LASTEXITCODE = 0
                return "Linux 用 Windows サブシステム Microsoft.WSL 2.7.3.0 winget"
            }

            $ctx.Options["WingetMode"] = "import"
            $ctx.Options["WingetVerifyCommandOnly"] = $true
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "1 個検証失敗"
            Should -Invoke Invoke-Winget -Times 1 -ParameterFilter { $Arguments -contains "install" }
            Should -Invoke Invoke-Winget -Times 1 -ParameterFilter { $Arguments -contains "repair" }
            Should -Invoke Invoke-Winget -Times 1 -ParameterFilter { $Arguments -contains "uninstall" }
            Should -Invoke Invoke-VerifyCommand -Times 3 -ParameterFilter {
                $Command -eq "wsl" -and
                $Arguments -contains "--version" -and
                $TimeoutSeconds -eq 30
            }
        }

        It 'should install Microsoft.WSL only when it is not installed and then require wsl --version to pass' {
            Mock Invoke-VerifyCommand {
                $global:LASTEXITCODE = 0
                return "WSL version: 2.7.3.0"
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "install") {
                    $global:LASTEXITCODE = 0
                    return "インストールが完了しました"
                }
                $global:LASTEXITCODE = 1
            }

            $ctx.Options["WingetMode"] = "import"
            $ctx.Options["WingetVerifyCommandOnly"] = $true
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "1 個インストール"
            Should -Invoke Invoke-Winget -Times 1 -ParameterFilter { $Arguments -contains "install" }
            Should -Invoke Invoke-VerifyCommand -Times 1 -ParameterFilter {
                $Command -eq "wsl" -and
                $Arguments -contains "--version" -and
                $TimeoutSeconds -eq 30
            }
        }

        It 'should treat winget already-installed failure as verification failure after repair and reinstall still fail' {
            Mock Invoke-VerifyCommand {
                $global:LASTEXITCODE = 124
                return "検証コマンドがタイムアウトしました (30s): wsl --version"
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "repair") {
                    $global:LASTEXITCODE = 0
                    return "修復が完了しました"
                }
                if ($Arguments -contains "uninstall") {
                    $global:LASTEXITCODE = 0
                    return "アンインストールが完了しました"
                }
                if ($Arguments -contains "install") {
                    if ($script:installAttempted) {
                        $global:LASTEXITCODE = 0
                        return "インストールが完了しました"
                    }
                    $script:installAttempted = $true
                    $global:LASTEXITCODE = 1
                    return @(
                        "このアプリケーションの別のバージョンが既にインストールされています。",
                        "インストーラーが終了コードで失敗しました: 0x80073cfb : The provided package is already installed"
                    )
                }
                $global:LASTEXITCODE = 1
            }
            $script:installAttempted = $false

            $ctx.Options["WingetMode"] = "import"
            $ctx.Options["WingetVerifyCommandOnly"] = $true
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "1 個検証失敗"
            $result.Message | Should -Not -Match "1 個失敗"
            Should -Invoke Invoke-Winget -Times 2 -ParameterFilter { $Arguments -contains "install" }
            Should -Invoke Invoke-Winget -Times 1 -ParameterFilter { $Arguments -contains "repair" }
            Should -Invoke Invoke-Winget -Times 1 -ParameterFilter { $Arguments -contains "uninstall" }
        }

        It 'should recover when winget repair makes wsl --version pass' {
            $script:verifyAttempts = 0
            Mock Invoke-VerifyCommand {
                $script:verifyAttempts++
                if ($script:verifyAttempts -eq 1) {
                    $global:LASTEXITCODE = 124
                    return "検証コマンドがタイムアウトしました (30s): wsl --version"
                }
                $global:LASTEXITCODE = 0
                return "WSL version: 2.7.3.0"
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "install") {
                    throw "winget install should be skipped when WSL repair succeeds"
                }
                if ($Arguments -contains "repair") {
                    $global:LASTEXITCODE = 0
                    return "修復が完了しました"
                }
                $global:LASTEXITCODE = 0
                return "Linux 用 Windows サブシステム Microsoft.WSL 2.7.3.0 winget"
            }

            $ctx.Options["WingetMode"] = "import"
            $ctx.Options["WingetVerifyCommandOnly"] = $true
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "1 個検証済み"
            Should -Invoke Invoke-Winget -Times 0 -ParameterFilter { $Arguments -contains "install" }
            Should -Invoke Invoke-Winget -Times 1 -ParameterFilter { $Arguments -contains "repair" }
        }

        It 'should recover when reinstall after repair makes wsl --version pass' {
            $script:verifyAttempts = 0
            Mock Invoke-VerifyCommand {
                $script:verifyAttempts++
                if ($script:verifyAttempts -lt 3) {
                    $global:LASTEXITCODE = 124
                    return "検証コマンドがタイムアウトしました (30s): wsl --version"
                }
                $global:LASTEXITCODE = 0
                return "WSL version: 2.7.3.0"
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "repair") {
                    $global:LASTEXITCODE = 0
                    return "修復が完了しました"
                }
                if ($Arguments -contains "uninstall") {
                    $global:LASTEXITCODE = 0
                    return "アンインストールが完了しました"
                }
                if ($Arguments -contains "install") {
                    $global:LASTEXITCODE = 0
                    return "インストールが完了しました"
                }
                $global:LASTEXITCODE = 0
                return "Linux 用 Windows サブシステム Microsoft.WSL 2.7.3.0 winget"
            }

            $ctx.Options["WingetMode"] = "import"
            $ctx.Options["WingetVerifyCommandOnly"] = $true
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "1 個検証済み"
            Should -Invoke Invoke-Winget -Times 1 -ParameterFilter { $Arguments -contains "repair" }
            Should -Invoke Invoke-Winget -Times 1 -ParameterFilter { $Arguments -contains "uninstall" }
            Should -Invoke Invoke-Winget -Times 1 -ParameterFilter { $Arguments -contains "install" }
            Should -Invoke Invoke-VerifyCommand -Times 3 -ParameterFilter {
                $Command -eq "wsl" -and
                $Arguments -contains "--version" -and
                $TimeoutSeconds -eq 30
            }
        }

        It 'should recover with reinstall when a fresh WSL install succeeds but runtime verification still fails' {
            $script:verifyAttempts = 0
            Mock Invoke-VerifyCommand {
                $script:verifyAttempts++
                if ($script:verifyAttempts -lt 3) {
                    $global:LASTEXITCODE = 124
                    return "検証コマンドがタイムアウトしました (30s): wsl --version"
                }
                $global:LASTEXITCODE = 0
                return "WSL version: 2.7.3.0"
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "repair") {
                    $global:LASTEXITCODE = 0
                    return "修復が完了しました"
                }
                if ($Arguments -contains "uninstall") {
                    $global:LASTEXITCODE = 0
                    return "アンインストールが完了しました"
                }
                if ($Arguments -contains "install") {
                    $global:LASTEXITCODE = 0
                    return "インストールが完了しました"
                }
                $global:LASTEXITCODE = 1
            }

            $ctx.Options["WingetMode"] = "import"
            $ctx.Options["WingetVerifyCommandOnly"] = $true
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "1 個検証済み"
            Should -Invoke Invoke-Winget -Times 2 -ParameterFilter { $Arguments -contains "install" }
            Should -Invoke Invoke-Winget -Times 1 -ParameterFilter { $Arguments -contains "repair" }
            Should -Invoke Invoke-Winget -Times 1 -ParameterFilter { $Arguments -contains "uninstall" }
            Should -Invoke Invoke-VerifyCommand -Times 3 -ParameterFilter {
                $Command -eq "wsl" -and
                $Arguments -contains "--version" -and
                $TimeoutSeconds -eq 30
            }
        }
    }

    Context 'Apply - import mode: nonzero install state' {
        BeforeEach {
            $script:installExitCode = 124
            $script:installOutput = "winget install timed out"
            $script:verifyCalls = 0
            $script:verifyShouldThrow = $true
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
            Mock Test-Path { return $false } -ParameterFilter { $Path -like "*\.cargo\bin" }
            Mock Write-Host { }
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "winget" }
                            Packages      = @(
                                [PSCustomObject]@{
                                    PackageIdentifier = "Slow.Tool"
                                    verifyCommand     = [PSCustomObject]@{ command = "slow-tool"; args = @("--version") }
                                }
                            )
                        }
                    )
                }
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "list") {
                    $global:LASTEXITCODE = 1
                    return
                }
                $global:LASTEXITCODE = $script:installExitCode
                return $script:installOutput
            }
            Mock Invoke-VerifyCommand {
                $script:verifyCalls++
                if ($script:verifyShouldThrow) {
                    throw "verification must be skipped after a failed install"
                }
                $global:LASTEXITCODE = 0
                return "1.0.0"
            }
        }

        It 'should skip verification when package installation times out' {
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "1 個失敗"
            $script:verifyCalls | Should -Be 0
            Should -Invoke Write-Host -Times 0 -ParameterFilter {
                [string]$Object -match '検証コマンド実行エラー|pathEntries の候補ディレクトリが見つかりません|command not found|not found'
            }
        }

        It 'should skip verification when a non-timeout install failure occurs' {
            $script:installExitCode = 1
            $script:installOutput = "fatal installer error"

            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "1 個失敗"
            $script:verifyCalls | Should -Be 0
            Should -Invoke Write-Host -Times 0 -ParameterFilter {
                [string]$Object -match '検証コマンド実行エラー|pathEntries の候補ディレクトリが見つかりません|command not found|not found'
            }
        }

        It 'should verify an already-installed no-op after a nonzero install exit' {
            $script:installExitCode = 1
            $script:installOutput = "No applicable update found"
            $script:verifyShouldThrow = $false

            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "1 個検証済み"
            $script:verifyCalls | Should -Be 1
        }

        It 'should verify installed Task and hadolint applications when PowerShell aliases shadow their names' {
            $originalPath = $env:PATH
            $commands = @('task', 'hadolint')
            $previousAliases = @{}
            $shimDirectory = Join-Path $TestDrive 'command-shims'
            $script:verificationCommandPaths = @()
            $script:wingetInstallCalls = 0
            New-Item -ItemType Directory -Path $shimDirectory -Force | Out-Null

            foreach ($command in $commands) {
                $existingAlias = Get-Alias -Name $command -ErrorAction SilentlyContinue
                if ($existingAlias) { $previousAliases[$command] = $existingAlias.Definition }
                Set-Alias -Name $command -Value Get-Date -Scope Global -Force
                Set-Content -LiteralPath (Join-Path $shimDirectory "$command.cmd") -Value '@exit /b 0' -Encoding ASCII
            }
            $env:PATH = "$shimDirectory$([IO.Path]::PathSeparator)$originalPath"
            Get-Command -Name task -CommandType Application -ErrorAction SilentlyContinue |
                Should -Not -BeNullOrEmpty

            try {
                Mock Get-JsonContent {
                    return [PSCustomObject]@{
                        Sources = @(
                            [PSCustomObject]@{
                                SourceDetails = [PSCustomObject]@{ Name = 'winget' }
                                Packages      = @(
                                    [PSCustomObject]@{
                                        PackageIdentifier = 'Task.Task'
                                        verifyCommand     = [PSCustomObject]@{ command = 'task'; args = @('--version') }
                                    },
                                    [PSCustomObject]@{
                                        PackageIdentifier = 'hadolint.hadolint'
                                        verifyCommand     = [PSCustomObject]@{ command = 'hadolint'; args = @('--version') }
                                    }
                                )
                            }
                        )
                    }
                }
                Mock Invoke-Winget {
                    param($Arguments)
                    if ($Arguments -contains 'list') {
                        $global:LASTEXITCODE = 0
                        return @(
                            'Name Id Version Source',
                            '-------------------',
                            'Task Task.Task 3.44.1 winget',
                            'hadolint hadolint.hadolint 2.14.0 winget'
                        )
                    }
                    $script:wingetInstallCalls++
                    $global:LASTEXITCODE = 1
                    return 'No applicable update found'
                }
                Mock Invoke-VerifyCommand {
                    param($Command)
                    $script:verificationCommandPaths += [string]$Command
                    if ($Command -in @(
                            (Join-Path $shimDirectory 'task.cmd'),
                            (Join-Path $shimDirectory 'hadolint.cmd')
                        )) {
                        $global:LASTEXITCODE = 0
                        return 'version'
                    }
                    $global:LASTEXITCODE = 127
                    return 'PowerShell alias shadowed the application'
                }

                $ctx.Options['WingetMode'] = 'import'
                $result = $handler.Apply($ctx)

                $script:verificationCommandPaths | Should -Contain (Join-Path $shimDirectory 'task.cmd')
                $script:verificationCommandPaths | Should -Contain (Join-Path $shimDirectory 'hadolint.cmd')
                $result.Message | Should -Match '2 個検証済み'
                $result.Success | Should -BeTrue
                $script:wingetInstallCalls | Should -Be 2
                Should -Invoke Invoke-Winget -Times 2 -ParameterFilter { $Arguments -contains 'install' }

                Remove-Item -LiteralPath (Join-Path $shimDirectory 'task.cmd'), (Join-Path $shimDirectory 'hadolint.cmd') -Force
                $script:verificationCommandPaths = @()
                $result = $handler.Apply($ctx)

                $result.Success | Should -BeFalse
                $result.Message | Should -Match '2 個検証失敗'
                $script:verificationCommandPaths | Should -BeNullOrEmpty
            }
            finally {
                $env:PATH = $originalPath
                foreach ($command in $commands) {
                    Remove-Item -LiteralPath "Alias:\$command" -Force -ErrorAction SilentlyContinue
                    if ($previousAliases.ContainsKey($command)) {
                        Set-Alias -Name $command -Value $previousAliases[$command] -Scope Global -Force
                    }
                }
            }
        }
    }

    Context 'EnsurePathEntries - installed WinGet command verification' {
        It 'should resolve the nine reported portable package commands from their package directories' {
            $originalPath = $env:PATH
            $originalLocalAppData = $env:LOCALAPPDATA
            $env:LOCALAPPDATA = Join-Path $TestDrive 'WinGetLocalAppData'
            $packagesRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
            $packageCommands = @(
                @{ Id = 'Task.Task'; Command = 'task' },
                @{ Id = 'hadolint.hadolint'; Command = 'hadolint' },
                @{ Id = 'Artempyanykh.Marksman'; Command = 'marksman' },
                @{ Id = 'astral-sh.ruff'; Command = 'ruff' },
                @{ Id = 'JohnnyMorganz.StyLua'; Command = 'stylua' },
                @{ Id = 'tamasfe.taplo'; Command = 'taplo' },
                @{ Id = 'tree-sitter.tree-sitter-cli'; Command = 'tree-sitter' },
                @{ Id = 'astral-sh.ty'; Command = 'ty' },
                @{ Id = 'astral-sh.uv'; Command = 'uv' }
            )
            Mock Set-UserEnvironmentPath { }

            try {
                foreach ($packageCommand in $packageCommands) {
                    $env:PATH = $originalPath
                    $packageDirectory = Join-Path $packagesRoot "$($packageCommand.Id)_Microsoft.Winget.Source_8wekyb3d8bbwe"
                    New-Item -ItemType Directory -Path $packageDirectory -Force | Out-Null
                    Set-Content -LiteralPath (Join-Path $packageDirectory "$($packageCommand.Command).cmd") -Value '@exit /b 0' -Encoding ASCII

                    $handler.EnsurePathEntriesQuiet([PSCustomObject]@{
                            PathEntries = @("%LOCALAPPDATA%\Microsoft\WinGet\Packages\$($packageCommand.Id)*")
                        })

                    $resolved = Get-Command -Name $packageCommand.Command -CommandType Application -ErrorAction SilentlyContinue |
                        Select-Object -First 1
                    $resolved | Should -Not -BeNullOrEmpty -Because "$($packageCommand.Id) must expose $($packageCommand.Command) after PATH setup"
                    $resolved.Source | Should -Be (Join-Path $packageDirectory "$($packageCommand.Command).cmd")
                }
            }
            finally {
                $env:PATH = $originalPath
                $env:LOCALAPPDATA = $originalLocalAppData
            }
        }
    }

    Context 'Apply - import mode: skipInstall package' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
            Mock Test-Path { return $false } -ParameterFilter { $Path -like "*\.cargo\bin" }
        }

        It 'should skip manual packages instead of invoking winget install' {
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "winget" }
                            Packages      = @(
                                [PSCustomObject]@{
                                    PackageIdentifier = "Manual.GUIApp"
                                    skipInstall       = $true
                                    skipReason        = "installer hangs in non-interactive winget"
                                }
                            )
                        }
                    )
                }
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "install") {
                    throw "winget install should be skipped"
                }
                $global:LASTEXITCODE = 1
            }
            Mock Write-Host { }

            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "1 個スキップ"
            Should -Invoke Invoke-Winget -Times 0 -ParameterFilter { $Arguments -contains "install" }
            Should -Invoke Write-Host -ParameterFilter {
                [string]$Object -match 'スキップ \(手動対象\): Manual\.GUIApp'
            }
        }

        It 'should install packages when verification is unavailable and skipInstall is absent' {
            $script:installInvoked = $false
            $script:weztermDir = Join-Path $TestDrive "WezTerm"
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "winget" }
                            Packages      = @(
                                [PSCustomObject]@{
                                    PackageIdentifier = "wez.wezterm.nightly"
                                    pathEntries       = @($script:weztermDir)
                                    verifyCommand     = [PSCustomObject]@{ command = "wezterm"; args = @("--version") }
                                }
                            )
                        }
                    )
                }
            }
            Mock Write-Host { }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "install") {
                    $script:installInvoked = $true
                    New-Item -ItemType Directory -Path $script:weztermDir -Force | Out-Null
                    $global:LASTEXITCODE = 0
                    return "installed wezterm"
                }
                $global:LASTEXITCODE = 1
            }
            Mock Invoke-VerifyCommand {
                if ($script:installInvoked) {
                    $global:LASTEXITCODE = 0
                    return "wezterm 20260607"
                }
                $global:LASTEXITCODE = 127
                throw "wezterm not found"
            }

            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "1 個インストール"
            Should -Invoke Invoke-Winget -Times 1 -ParameterFilter { $Arguments -contains "install" }
            Should -Invoke Write-Host -Times 0 -ParameterFilter {
                [string]$Object -match '検証コマンド実行エラー|pathEntries の候補ディレクトリが見つかりません'
            }
        }
    }

    Context 'Apply - import mode: mixed packages with and without verifyCommand' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "winget" }
                            Packages      = @(
                                [PSCustomObject]@{ PackageIdentifier = "GUI.App" },
                                [PSCustomObject]@{ PackageIdentifier = "CLI.Tool"; verifyCommand = [PSCustomObject]@{ command = "cli-tool"; args = @("--version") } }
                            )
                        }
                    )
                }
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "list") { $global:LASTEXITCODE = 1 } else { $global:LASTEXITCODE = 0 }
            }
            Mock Invoke-VerifyCommand { $global:LASTEXITCODE = 0; return "1.0.0" }
            Mock Test-Path { return $false } -ParameterFilter { $Path -like "*\.cargo\bin" }
        }

        It 'should install packages with and without verifyCommand and verify only the configured command' {
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "2 個インストール"
            Should -Invoke Invoke-VerifyCommand -Times 1 -ParameterFilter {
                $Command -eq "cli-tool" -and $Arguments -contains "--version"
            }
        }
    }

    Context 'Apply - import mode: administrator packages' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "winget" }
                            Packages      = @(
                                [PSCustomObject]@{
                                    PackageIdentifier = "AutoHotkey.AutoHotkey"
                                    requiresAdmin     = $true
                                    installArgs       = @("--scope", "machine")
                                }
                            )
                        }
                    )
                }
            }
            Mock Invoke-Winget {
                throw "user phase must not invoke administrator package install"
            }
        }

        It 'should defer administrator packages without invoking winget in user phase' {
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "管理者フェーズ"
            Should -Invoke Invoke-Winget -Times 0
        }
    }

    Context 'Apply - import mode: direct archive fallback' {
        BeforeEach {
            $script:directDestination = Join-Path $TestDrive "Bun"
            $script:verifyAttempts = 0
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "winget" }
                            Packages      = @(
                                [PSCustomObject]@{
                                    PackageIdentifier = "Oven-sh.Bun"
                                    directInstaller   = [PSCustomObject]@{
                                        type           = "archive"
                                        url            = "https://example.invalid/bun.zip"
                                        sha256         = ("ab" * 32)
                                        destination    = $script:directDestination
                                        executable     = "bun.exe"
                                        timeoutSeconds = 30
                                    }
                                    pathEntries       = @($script:directDestination)
                                    verifyCommand     = [PSCustomObject]@{ command = "bun"; args = @("--version") }
                                }
                            )
                        }
                    )
                }
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "list") {
                    $global:LASTEXITCODE = 0
                    return @("Name Id Version Source", "-------------------")
                }
                if ($Arguments -contains "install") {
                    $global:LASTEXITCODE = 124
                    return "winget timed out after downloading the archive"
                }
                $global:LASTEXITCODE = 0
            }
            Mock Invoke-VerifyCommand {
                $script:verifyAttempts++
                if ($script:verifyAttempts -eq 1) {
                    $global:LASTEXITCODE = 1
                    throw "bun not found"
                }
                $global:LASTEXITCODE = 0
                return "1.4.2"
            }
            Mock Invoke-WebRequest {
                param($OutFile)
                New-Item -ItemType File -Path $OutFile -Force | Out-Null
            }
            Mock Get-FileHash {
                [PSCustomObject]@{ Hash = ("ab" * 32).ToUpperInvariant() }
            }
            Mock Expand-Archive {
                param($DestinationPath)
                New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
                New-Item -ItemType File -Path (Join-Path $DestinationPath "bun.exe") -Force | Out-Null
            }
        }

        It 'should use the direct archive after WinGet fails and retain the original failure diagnostics' {
            $script:loggedMessages = @()
            Mock Write-Host {
                param($Object)
                $script:loggedMessages += [string]$Object
            }
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "1 個インストール"
            Should -Invoke Invoke-WebRequest -Times 1
            Test-Path -LiteralPath (Join-Path $script:directDestination "bun.exe") -PathType Leaf | Should -Be $true
            Get-Content -LiteralPath (Join-Path $script:directDestination ".dotfiles-direct-installer.sha256") -Raw |
                Should -Be (("ab" * 32).ToUpperInvariant() + [Environment]::NewLine)
            # The installed-package pre-check may run once; the timed-out
            # install must not trigger a second verification attempt.
            $script:verifyAttempts | Should -Be 1
            ($script:loggedMessages -join "`n") | Should -Match "exit code 124"
            ($script:loggedMessages -join "`n") | Should -Match "winget timed out after downloading the archive"
        }

        It 'should repair an installed Codex CLI with no adjacent host from the direct archive' {
            $env:LOCALAPPDATA = Join-Path $TestDrive 'LocalAppData'
            New-Item -ItemType Directory -Path $env:LOCALAPPDATA -Force | Out-Null
            $script:codexDestination = Join-Path $TestDrive 'CodexRepair'
            $script:directInstallerCalls = 0
            $script:verifyCalls = 0
            $script:loggedMessages = @()
            Mock Get-JsonContent {
                [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = 'winget' }
                            Packages = @(
                                [PSCustomObject]@{
                                    PackageIdentifier = 'OpenAI.Codex'
                                    directInstaller = [PSCustomObject]@{
                                        type = 'archive'
                                        url = 'https://example.invalid/codex.zip'
                                        sha256 = ('cd' * 32)
                                        destination = $script:codexDestination
                                        executable = 'bin\codex.exe'
                                        timeoutSeconds = 30
                                    }
                                    verifyCommand = [PSCustomObject]@{ command = 'codex'; args = @('--version') }
                                }
                            )
                        }
                    )
                }
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains 'list' -and $Arguments -notcontains '--id') {
                    $global:LASTEXITCODE = 0
                    return @('Name Id Version Source', '-------------------', 'Codex OpenAI.Codex 1.0 winget')
                }
                if ($Arguments -contains 'install') {
                    $global:LASTEXITCODE = 1
                    return 'No applicable update found'
                }
                $global:LASTEXITCODE = 1
                return @()
            }
            Mock Invoke-VerifyCommand {
                $script:verifyCalls++
                $global:LASTEXITCODE = 0
                return 'codex 1.0.0'
            }
            Mock Invoke-WebRequest {
                param($OutFile)
                Set-Content -LiteralPath $OutFile -Value 'Codex archive fixture' -NoNewline
            }
            Mock Get-FileHash { [PSCustomObject]@{ Hash = ('cd' * 32).ToUpperInvariant() } }
            Mock Expand-Archive {
                param($DestinationPath)
                $binPath = Join-Path $DestinationPath 'bin'
                New-Item -ItemType Directory -Path $binPath -Force | Out-Null
                [System.IO.File]::WriteAllText((Join-Path $binPath 'codex.exe'), 'repaired CLI')
                [System.IO.File]::WriteAllText((Join-Path $binPath 'codex-code-mode-host.exe'), 'repaired host')
            }
            Mock Write-Host {
                param($Object)
                $script:loggedMessages += [string]$Object
            }

            $ctx.Options['WingetMode'] = 'import'
            $result = $handler.Apply($ctx)

            $result.Success | Should -BeTrue -Because "$($result.Message): $($script:loggedMessages -join '; ')"
            Should -Invoke Invoke-WebRequest -Times 1
            (Join-Path $script:codexDestination 'bin\codex.exe') | Should -Exist
            (Join-Path $script:codexDestination 'bin\codex-code-mode-host.exe') | Should -Exist
            $script:verifyCalls | Should -BeGreaterThan 0
            ($script:loggedMessages -join "`n") | Should -Match 'Codex.*host'
        }

        It 'should preserve both Codex executables when installing the complete tar.gz package' {
            $fixtureRoot = Join-Path $TestDrive "CodexTarFixture"
            $fixtureBin = Join-Path $fixtureRoot "bin"
            $script:codexDestination = Join-Path $TestDrive "CodexTarInstall"
            $script:codexArchive = Join-Path $TestDrive "codex-package.tar.gz"
            $script:codexArchiveHash = ("ef" * 32).ToUpperInvariant()
            $script:codexVerificationAttempts = 0
            $codexExecutable = "bin\codex.exe"
            $codeModeHost = "codex-code-mode-host.exe"
            New-Item -ItemType Directory -Path $fixtureBin -Force | Out-Null
            [System.IO.File]::WriteAllBytes(
                (Join-Path $fixtureBin "codex.exe"),
                [System.Text.Encoding]::ASCII.GetBytes("codex cli fixture payload")
            )
            [System.IO.File]::WriteAllBytes(
                (Join-Path $fixtureBin $codeModeHost),
                [System.Text.Encoding]::ASCII.GetBytes("codex code mode host fixture payload")
            )
            $tar = Get-Command tar.exe -ErrorAction Stop
            & $tar.Source -czf $script:codexArchive -C $fixtureRoot bin 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Could not create Codex tar.gz test fixture (exit code $LASTEXITCODE)"
            }

            # Keep real tar extraction in this test, but avoid ProcessStartInfo
            # stream/encoding behavior (which differs between Windows PowerShell
            # 5.1 and PowerShell 7). The native invocation explicitly captures
            # both output streams, as the production wrapper does.
            Mock Invoke-ExternalCommandWithTimeout {
                param($Command, $Arguments, $TimeoutSeconds)
                $output = @(& $Command @Arguments 2>&1 | ForEach-Object { [string]$_ })
                $tarExitCode = $LASTEXITCODE
                $global:LASTEXITCODE = $tarExitCode
                return $output
            } -ParameterFilter { $Command -eq 'tar.exe' }

            Mock Get-JsonContent {
                [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "winget" }
                            Packages      = @(
                                [PSCustomObject]@{
                                    PackageIdentifier = "OpenAI.Codex"
                                    directInstaller   = [PSCustomObject]@{
                                        type           = "archive"
                                        url            = "https://example.invalid/codex-package-x86_64-pc-windows-msvc.tar.gz"
                                        sha256         = $script:codexArchiveHash
                                        destination    = $script:codexDestination
                                        executable     = $codexExecutable
                                        timeoutSeconds = 30
                                    }
                                    pathEntries       = @($script:codexDestination)
                                    verifyCommand     = [PSCustomObject]@{ command = "codex"; args = @("--version") }
                                }
                            )
                        }
                    )
                }
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "list") {
                    $global:LASTEXITCODE = 0
                    return @("Name Id Version Source", "-------------------")
                }
                if ($Arguments -contains "install") {
                    $global:LASTEXITCODE = 1
                    return "winget source unavailable while installing Codex"
                }
                $global:LASTEXITCODE = 0
                return @()
            }
            Mock Invoke-VerifyCommand {
                $script:codexVerificationAttempts++
                if ($script:codexVerificationAttempts -eq 1) {
                    $global:LASTEXITCODE = 1
                    throw "codex not found before installation"
                }
                $global:LASTEXITCODE = 0
                return "codex 0.156.1"
            }
            Mock Invoke-WebRequest {
                param($OutFile)
                Copy-Item -LiteralPath $script:codexArchive -Destination $OutFile -Force
            }
            Mock Get-FileHash {
                [PSCustomObject]@{ Hash = $script:codexArchiveHash }
            }

            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -BeTrue
            (Join-Path $script:codexDestination $codexExecutable) | Should -Exist
            (Join-Path $script:codexDestination "bin\$codeModeHost") | Should -Exist
            [System.IO.File]::ReadAllText((Join-Path $script:codexDestination $codexExecutable)) |
                Should -Be "codex cli fixture payload"
            [System.IO.File]::ReadAllText((Join-Path $script:codexDestination "bin\$codeModeHost")) |
                Should -Be "codex code mode host fixture payload"
            $script:codexVerificationAttempts | Should -Be 2
        }

        It 'should repair an installed Codex CLI missing its adjacent host through the direct archive' {
            $env:LOCALAPPDATA = Join-Path $TestDrive 'LocalAppData'
            $script:codexDestination = Join-Path $TestDrive 'CodexMissingHost'
            $script:codexHash = ('cd' * 32).ToUpperInvariant()
            $script:archiveDownloads = 0
            $codexBin = Join-Path $script:codexDestination 'bin'
            New-Item -ItemType Directory -Path $codexBin -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $codexBin 'codex.exe') -Value 'existing CLI' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $script:codexDestination '.dotfiles-direct-installer.sha256') -Value $script:codexHash -Encoding ASCII

            Mock Get-JsonContent {
                [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = 'winget' }
                            Packages = @(
                                [PSCustomObject]@{
                                    PackageIdentifier = 'OpenAI.Codex'
                                    directInstaller = [PSCustomObject]@{
                                        type = 'archive'
                                        url = 'https://example.invalid/codex-package.zip'
                                        sha256 = $script:codexHash
                                        destination = $script:codexDestination
                                        executable = 'bin\codex.exe'
                                        timeoutSeconds = 30
                                    }
                                    verifyCommand = [PSCustomObject]@{ command = 'codex'; args = @('--version') }
                                }
                            )
                        }
                    )
                }
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains 'list' -and $Arguments -notcontains '--id') {
                    $global:LASTEXITCODE = 0
                    return @('Name Id Version Source', '-------------------', 'Codex OpenAI.Codex 1.0 winget')
                }
                if ($Arguments -contains 'install') {
                    $global:LASTEXITCODE = 0
                    return 'Successfully installed'
                }
                $global:LASTEXITCODE = 0
                return @()
            }
            Mock Invoke-VerifyCommand { $global:LASTEXITCODE = 0; return 'codex 1.0.0' }
            Mock Invoke-WebRequest { $script:archiveDownloads++; Set-Content -LiteralPath $OutFile -Value 'archive' -Encoding ASCII }
            Mock Get-FileHash { [PSCustomObject]@{ Hash = $script:codexHash } }
            Mock Expand-Archive {
                param($DestinationPath)
                $bin = Join-Path $DestinationPath 'bin'
                New-Item -ItemType Directory -Path $bin -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $bin 'codex.exe') -Value 'repaired CLI' -Encoding ASCII
                Set-Content -LiteralPath (Join-Path $bin 'codex-code-mode-host.exe') -Value 'repaired host' -Encoding ASCII
            }

            $ctx.Options['WingetMode'] = 'import'
            $result = $handler.Apply($ctx)

            $result.Success | Should -BeTrue
            $script:archiveDownloads | Should -Be 1
            (Join-Path $script:codexDestination 'bin\codex.exe') | Should -Exist
            (Join-Path $script:codexDestination 'bin\codex-code-mode-host.exe') | Should -Exist
            [System.IO.File]::ReadAllText((Join-Path $script:codexDestination 'bin\codex.exe')).Trim() | Should -Be 'repaired CLI'
            [System.IO.File]::ReadAllText((Join-Path $script:codexDestination 'bin\codex-code-mode-host.exe')).Trim() | Should -Be 'repaired host'
        }

        It 'should run the WinGet latest-version check but not fallback for verified installed Codex' {
            $script:codexDestination = Join-Path $TestDrive "Codex"
            $script:codexHash = ("cd" * 32).ToUpperInvariant()
            New-Item -ItemType Directory -Path $script:codexDestination -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $script:codexDestination "codex.exe") -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $script:codexDestination "codex-code-mode-host.exe") -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $script:codexDestination ".dotfiles-direct-installer.sha256") -Value $script:codexHash -Encoding ASCII
            $script:installCalls = 0
            $script:webRequestCalls = 0
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "winget" }
                            Packages      = @(
                                [PSCustomObject]@{
                                    PackageIdentifier = "OpenAI.Codex"
                                    directInstaller   = [PSCustomObject]@{
                                        type           = "archive"
                                        url            = "https://example.invalid/codex.zip"
                                        sha256         = $script:codexHash
                                        destination    = $script:codexDestination
                                        executable     = "codex.exe"
                                        timeoutSeconds = 30
                                    }
                                    verifyCommand     = [PSCustomObject]@{ command = "codex"; args = @("--version") }
                                }
                            )
                        }
                    )
                }
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "list" -and $Arguments -notcontains "--id") {
                    $global:LASTEXITCODE = 0
                    return @("Name Id Version Source", "-------------------", "Codex OpenAI.Codex 1.0 winget")
                }
                if ($Arguments -contains "install") {
                    $script:installCalls++
                    $global:LASTEXITCODE = 1
                    return "No applicable update found"
                }
                $global:LASTEXITCODE = 1
                return @()
            }
            Mock Invoke-VerifyCommand { $global:LASTEXITCODE = 0; return "codex 1.0.0" }
            Mock Invoke-WebRequest { $script:webRequestCalls++ }

            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "1 個検証済み"
            $script:installCalls | Should -Be 1
            $script:webRequestCalls | Should -Be 0
        }

        It 'should keep installed Codex network failures visible without direct fallback' {
            $script:codexDestination = Join-Path $TestDrive "CodexNetwork"
            New-Item -ItemType Directory -Path $script:codexDestination -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $script:codexDestination "codex.exe") -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $script:codexDestination "codex-code-mode-host.exe") -Force | Out-Null
            $script:installCalls = 0
            $script:webRequestCalls = 0
            $script:loggedMessages = @()
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "winget" }
                            Packages      = @(
                                [PSCustomObject]@{
                                    PackageIdentifier = "OpenAI.Codex"
                                    directInstaller   = [PSCustomObject]@{
                                        type           = "archive"
                                        url            = "https://example.invalid/codex.zip"
                                        sha256         = ("cd" * 32)
                                        destination    = $script:codexDestination
                                        executable     = "codex.exe"
                                        timeoutSeconds = 30
                                    }
                                    verifyCommand     = [PSCustomObject]@{ command = "codex"; args = @("--version") }
                                }
                            )
                        }
                    )
                }
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "list" -and $Arguments -notcontains "--id") {
                    $global:LASTEXITCODE = 0
                    return @("Name Id Version Source", "-------------------", "Codex OpenAI.Codex 1.0 winget")
                }
                if ($Arguments -contains "install") {
                    $script:installCalls++
                    $global:LASTEXITCODE = 1
                    return "Failed when opening source: network unreachable"
                }
                $global:LASTEXITCODE = 1
                return @()
            }
            Mock Invoke-VerifyCommand { $global:LASTEXITCODE = 0; return "codex 1.0.0" }
            Mock Invoke-WebRequest { $script:webRequestCalls++ }
            Mock Write-Host {
                param($Object)
                $script:loggedMessages += [string]$Object
            }

            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "1 個失敗"
            $script:installCalls | Should -Be 1
            $script:webRequestCalls | Should -Be 0
            ($script:loggedMessages -join "`n") | Should -Match "network unreachable"
            ($script:loggedMessages -join "`n") | Should -Match "exit code: 1"
        }

        It 'should not accept a stale direct-installer marker after fallback fails' {
            New-Item -ItemType Directory -Path $script:directDestination -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $script:directDestination "bun.exe") -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $script:directDestination ".dotfiles-direct-installer.sha256") -Value (("ab" * 32).ToUpperInvariant())
            Mock Invoke-WebRequest { throw "download failed" }

            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -BeFalse
            $result.Message | Should -Match "1 個失敗"
            $result.Message | Should -Not -Match "1 個インストール"
        }

        It 'should restore the existing archive destination when replacement copy fails' {
            $oldExecutable = Join-Path $script:directDestination "bun.exe"
            New-Item -ItemType Directory -Path $script:directDestination -Force | Out-Null
            Set-Content -LiteralPath $oldExecutable -Value "old archive"
            Set-Content -LiteralPath (Join-Path $script:directDestination ".dotfiles-direct-installer.sha256") -Value "old-marker"
            Mock Copy-Item { throw "copy failed" }

            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -BeFalse
            Test-Path -LiteralPath $oldExecutable -PathType Leaf | Should -BeTrue
            Get-Content -LiteralPath $oldExecutable -Raw | Should -Be "old archive`r`n"
            Get-Content -LiteralPath (Join-Path $script:directDestination ".dotfiles-direct-installer.sha256") -Raw |
                Should -Be "old-marker`r`n"
        }

        It 'should replace the existing archive destination and preserve the new marker' {
            $oldExecutable = Join-Path $script:directDestination "bun.exe"
            New-Item -ItemType Directory -Path $script:directDestination -Force | Out-Null
            Set-Content -LiteralPath $oldExecutable -Value "old archive"
            Set-Content -LiteralPath (Join-Path $script:directDestination ".dotfiles-direct-installer.sha256") -Value "old-marker"

            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -BeTrue
            Test-Path -LiteralPath $oldExecutable -PathType Leaf | Should -BeTrue
            Get-Content -LiteralPath $oldExecutable -Raw | Should -Not -Be "old archive`r`n"
            Get-Content -LiteralPath (Join-Path $script:directDestination ".dotfiles-direct-installer.sha256") -Raw |
                Should -Be (("ab" * 32).ToUpperInvariant() + [Environment]::NewLine)
        }

        It 'should support a direct file fallback for portable binaries without an archive' {
            $fileDestination = Join-Path $TestDrive "direnv"
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "list") {
                    $global:LASTEXITCODE = 1
                    return @()
                }
                if ($Arguments -contains "install") {
                    $global:LASTEXITCODE = 124
                    return "winget timed out before installing the package"
                }
                $global:LASTEXITCODE = 1
            }
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "winget" }
                            Packages      = @(
                                [PSCustomObject]@{
                                    PackageIdentifier = "direnv.direnv"
                                    directInstaller   = [PSCustomObject]@{
                                        type           = "file"
                                        url            = "https://example.invalid/direnv"
                                        sha256         = ("cd" * 32)
                                        destination    = $fileDestination
                                        executable     = "direnv.exe"
                                        timeoutSeconds = 30
                                    }
                                    pathEntries       = @($fileDestination)
                                    verifyCommand     = [PSCustomObject]@{ command = "direnv"; args = @("--version") }
                                }
                            )
                        }
                    )
                }
            }
            Mock Invoke-WebRequest {
                param($OutFile)
                New-Item -ItemType File -Path $OutFile -Force | Out-Null
            }
            Mock Get-FileHash {
                [PSCustomObject]@{ Hash = ("cd" * 32).ToUpperInvariant() }
            }
            Mock Invoke-VerifyCommand {
                $global:LASTEXITCODE = 0
                return "2.37.1"
            }

            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            Test-Path -LiteralPath (Join-Path $fileDestination "direnv.exe") -PathType Leaf | Should -Be $true
            Should -Invoke Expand-Archive -Times 0
        }
    }

}
