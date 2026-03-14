BeforeAll {
    # ソースファイルの読み込み
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.Winget.ps1
}

Describe 'WingetHandler' {
    BeforeEach {
        $script:handler = [WingetHandler]::new()
        $script:ctx = [SetupContext]::new("D:\dotfiles")
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
            } else {
                $handler.$property | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'CanApply - winget not found' {
        BeforeEach {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExist { return $true }
        }

        It 'should return false' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $false
        }
    }

    Context 'CanApply - import mode without package file' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
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
                                [PSCustomObject]@{ PackageIdentifier = "Git.Git" },
                                [PSCustomObject]@{ PackageIdentifier = "twpayne.chezmoi" }
                            )
                        }
                    )
                }
            }
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "list") {
                    $global:LASTEXITCODE = 1
                } else {
                    $global:LASTEXITCODE = 0
                }
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
                } elseif ($Arguments -contains "install") {
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
                $global:LASTEXITCODE = 0
            }
            Mock Test-Path { return $false } -ParameterFilter { $Path -like "*\.cargo\bin" }
        }

        It 'should skip and return success' {
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "インストール済み"
        }

        It 'should not call winget install' {
            $script:installCalled = $false
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains "install") {
                    $script:installCalled = $true
                }
                $global:LASTEXITCODE = 0
            }
            $ctx.Options["WingetMode"] = "import"
            $handler.Apply($ctx)
            $script:installCalled | Should -Be $false
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
                } else {
                    $global:LASTEXITCODE = 1
                }
            }
            Mock Test-Path { return $false } -ParameterFilter { $Path -like "*\.cargo\bin" }
        }

        It 'should return success with partial failure warning' {
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "一部失敗"
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
                } else {
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
                } else {
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

}
