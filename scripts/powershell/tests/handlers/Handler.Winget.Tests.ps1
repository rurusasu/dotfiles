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
            # machine scope インストール成功
            Mock Invoke-WingetInstall {
                [PSCustomObject]@{ Output = @("Successfully installed"); ExitCode = 0 }
            }
        }

        It 'should return success result' {
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "インストール"
        }

        It 'should call winget install for each package' {
            $script:installCalls = @()
            Mock Invoke-WingetInstall {
                param($Arguments)
                if ($Arguments -contains "install") {
                    $script:installCalls += $Arguments | Where-Object { $_ -notmatch "^-" -and $_ -ne "install" -and $_ -ne "machine" -and $_ -ne "user" } | Select-Object -First 1
                }
                [PSCustomObject]@{ Output = @(); ExitCode = 0 }
            }
            $ctx.Options["WingetMode"] = "import"
            $handler.Apply($ctx)
            $script:installCalls | Should -Contain "Git.Git"
            $script:installCalls | Should -Contain "twpayne.chezmoi"
        }

        It 'should use --scope machine' {
            $script:capturedArgs = @()
            Mock Invoke-WingetInstall {
                param($Arguments)
                $script:capturedArgs = $Arguments
                [PSCustomObject]@{ Output = @(); ExitCode = 0 }
            }
            $ctx.Options["WingetMode"] = "import"
            $handler.Apply($ctx)
            $script:capturedArgs | Should -Contain "--scope"
            $script:capturedArgs | Should -Contain "machine"
        }
    }

    Context 'Apply - import mode: all packages already installed (machine scope)' {
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
            # PACKAGE_ALREADY_INSTALLED 終了コード (0x8A150011 = -1978335215)
            Mock Invoke-WingetInstall {
                [PSCustomObject]@{ Output = @("Package already installed."); ExitCode = -1978335215 }
            }
        }

        It 'should skip and count as skipped' {
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "スキップ"
        }

        It 'should not retry user scope when already installed at machine scope' {
            $script:callCount = 0
            Mock Invoke-WingetInstall {
                $script:callCount++
                [PSCustomObject]@{ Output = @("Package already installed."); ExitCode = -1978335215 }
            }
            $ctx.Options["WingetMode"] = "import"
            $handler.Apply($ctx)
            # ALREADY_INSTALLED は user scope リトライ不要 (1回のみ呼び出し)
            $script:callCount | Should -Be 1
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
            Mock Invoke-WingetInstall {
                [PSCustomObject]@{ Output = @("Error: package not found"); ExitCode = 1 }
            }
        }

        It 'should return success with partial failure warning' {
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "一部失敗"
        }
    }

    Context 'Apply - import mode: machine scope fails, user scope succeeds' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "winget" }
                            Packages      = @(
                                [PSCustomObject]@{ PackageIdentifier = "UserScope.App" }
                            )
                        }
                    )
                }
            }
        }

        It 'should install with user scope when machine scope fails' {
            $script:callCount = 0
            Mock Invoke-WingetInstall {
                $script:callCount++
                if ($script:callCount -eq 1) {
                    [PSCustomObject]@{ Output = @("machine scope not supported"); ExitCode = 1 }
                } else {
                    [PSCustomObject]@{ Output = @("Installed"); ExitCode = 0 }
                }
            }
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "インストール"
            $script:callCount | Should -Be 2
        }

        It 'should count user scope already-installed as skipped' {
            $script:callCount = 0
            Mock Invoke-WingetInstall {
                $script:callCount++
                if ($script:callCount -eq 1) {
                    [PSCustomObject]@{ Output = @(); ExitCode = 1 }
                } else {
                    [PSCustomObject]@{ Output = @("Package already installed."); ExitCode = -1978335215 }
                }
            }
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "スキップ"
        }

        It 'should skip and warn when admin context blocks user scope install (0x8A15002B)' {
            $script:callCount = 0
            Mock Invoke-WingetInstall {
                $script:callCount++
                if ($script:callCount -eq 1) {
                    # machine scope 失敗
                    [PSCustomObject]@{ Output = @(); ExitCode = 1 }
                } else {
                    # user scope: 0x8A15002B = already installed / no upgrade applicable
                    [PSCustomObject]@{ Output = @("Package already installed. Attempting to upgrade..."; "No applicable upgrade found."); ExitCode = -1978335189 }
                }
            }
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            # no-upgrade は skip 扱い (fail ではない)
            $result.Message | Should -Not -Match "一部失敗"
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
            Mock Invoke-WingetInstall {
                [PSCustomObject]@{ Output = @(); ExitCode = 0 }
            }
        }

        It 'should pass --source msstore for msstore packages' {
            $script:capturedArgs = $null
            Mock Invoke-WingetInstall {
                param($Arguments)
                $script:capturedArgs = $Arguments
                [PSCustomObject]@{ Output = @(); ExitCode = 0 }
            }
            $ctx.Options["WingetMode"] = "import"
            $handler.Apply($ctx)
            $script:capturedArgs | Should -Contain "--source"
            $script:capturedArgs | Should -Contain "msstore"
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
            Mock Invoke-WingetInstall {
                [PSCustomObject]@{ Output = @(); ExitCode = -1978335215 }
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
            Mock Invoke-WingetInstall {
                [PSCustomObject]@{ Output = @(); ExitCode = -1978335215 }
            }
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
            Mock Invoke-WingetInstall {
                [PSCustomObject]@{ Output = @(); ExitCode = -1978335215 }
            }
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
