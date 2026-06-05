BeforeAll {
    Set-StrictMode -Version Latest
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.Winget.ps1
}

Describe 'WingetHandler' {
    BeforeEach {
        $script:handler = [WingetHandler]::new()
        $script:ctx = [SetupContext]::new("D:\dotfiles")
        Mock Update-ProcessEnvironmentPath { }
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
            Mock Invoke-VerifyCommand { $global:LASTEXITCODE = 0; return "1.0.0" }
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

        It 'should skip and return success' {
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "1 個スキップ"
        }

        It 'should not call winget install' {
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
            $handler.Apply($ctx)
            $script:installCalled | Should -Be $false
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
                                [PSCustomObject]@{ PackageIdentifier = "9NT1R1C2HH7J" }
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
                                [PSCustomObject]@{ PackageIdentifier = "9NT1R1C2HH7J" }
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
                        "Windows Terminal  9NT1R1C2HH7J  1.19.0   msstore"
                    )
                }
                $global:LASTEXITCODE = 0
            }
            Mock Test-Path { return $false } -ParameterFilter { $Path -like "*\.cargo\bin" }
        }

        It 'should skip without calling install' {
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
                        "Windows Terminal  9NT1R1C2HH7J  1.19.0   msstore"
                    )
                }
                $global:LASTEXITCODE = 0
            }
            $ctx.Options["WingetMode"] = "import"
            $handler.Apply($ctx)
            $script:installCalled | Should -Be $false
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

        It 'should treat as not installed and attempt install' {
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "インストール"
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
            $cargoBin = Join-Path $env:USERPROFILE ".cargo\bin"
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
            Mock Test-Path { return $false } -ParameterFilter { $Path -like "*\.cargo\bin" }
        }

        It 'should install only packages with verifyCommand' {
            $script:installIds = @()
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
            Mock Invoke-VerifyCommand { $global:LASTEXITCODE = 0; return "PowerShell 7.6.2" }
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
        }
        AfterEach {
            $env:LOCALAPPDATA = $script:origLocalAppData
            $env:USERPROFILE = $script:origUserProfile
        }

        It 'should create command shim before verification' {
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\oxlint.exe" | Should -Exist
            Should -Invoke Invoke-VerifyCommand -Times 1
            Should -Invoke Set-UserEnvironmentPath -Times 1
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
    }

    Context 'Apply - import mode: package without verifyCommand' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "winget" }
                            Packages      = @(
                                [PSCustomObject]@{ PackageIdentifier = "GUI.App" }
                            )
                        }
                    )
                }
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "list") { $global:LASTEXITCODE = 1 } else { $global:LASTEXITCODE = 0 }
            }
            Mock Invoke-VerifyCommand { }
            Mock Test-Path { return $false } -ParameterFilter { $Path -like "*\.cargo\bin" }
        }

        It 'should count as installed without running verify' {
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "1 個インストール"
            Should -Invoke Invoke-VerifyCommand -Times 0
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

        It 'should install all packages and return success when some lack verifyCommand' {
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "2 個インストール"
        }

        It 'should run verify only for packages that have verifyCommand' {
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            Should -Invoke Invoke-VerifyCommand -Times 1
        }
    }

}
