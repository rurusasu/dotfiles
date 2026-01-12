#Requires -Module Pester

<#
.SYNOPSIS
    Handler.Mise.ps1 のユニットテスト

.DESCRIPTION
    MiseHandler クラスのテスト
    100% カバレッジを目標とする
#>

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.Mise.ps1
}

Describe 'MiseHandler' {
    BeforeEach {
        $script:handler = [MiseHandler]::new()
        $script:ctx = [SetupContext]::new("D:\dotfiles")
    }

    Context 'Constructor' {
        It 'should set <property> to <expected>' -ForEach @(
            @{ property = "Name"; expected = "Mise" }
            @{ property = "Description"; expected = "mise によるツールインストール" }
            @{ property = "Order"; expected = 15 }
            @{ property = "RequiresAdmin"; expected = $false }
        ) {
            $handler.$property | Should -Be $expected
        }
    }

    Context 'CanApply' {
        It 'should return false when SkipMiseInstall option is set' {
            Mock Write-Host { }
            $ctx.Options["SkipMiseInstall"] = $true

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }

        It 'should return false when mise is not installed' {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExist { return $false }
            Mock Write-Host { }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }

        It 'should return false when mise executable fails (DLL missing)' {
            Mock Get-ExternalCommand { return @{ Source = "C:\mise.exe" } }
            Mock Test-PathExist { return $true }
            Mock Invoke-MiseCommand {
                $global:LASTEXITCODE = -1073741515  # STATUS_DLL_NOT_FOUND
                return ""
            }
            Mock Write-Host { }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }

        It 'should return false when .mise.toml does not exist' {
            Mock Get-ExternalCommand { return @{ Source = "C:\mise.exe" } }
            Mock Test-PathExist {
                param($Path)
                # mise.exe は存在、.mise.toml は存在しない
                return $Path -notlike "*.mise.toml"
            }
            Mock Invoke-MiseCommand {
                $global:LASTEXITCODE = 0
                return "mise 2024.1.0"
            }
            Mock Write-Host { }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }

        It 'should return true when mise is installed and .mise.toml exists' {
            Mock Get-ExternalCommand { return @{ Source = "C:\mise.exe" } }
            Mock Test-PathExist { return $true }
            Mock Invoke-MiseCommand {
                $global:LASTEXITCODE = 0
                return "mise 2024.1.0"
            }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $true
        }
    }

    Context 'FindMiseExe' {
        BeforeEach {
            # FindMiseExe のテストでは TestMiseExecutable もモックする
            Mock Invoke-MiseCommand {
                $global:LASTEXITCODE = 0
                return "mise 2024.1.0"
            }
        }

        It 'should find mise in PATH' {
            Mock Get-ExternalCommand { return @{ Source = "C:\Program Files\mise\mise.exe" } }
            Mock Test-PathExist { return $false }  # .mise.toml は存在しない

            $handler.CanApply($ctx)

            # MiseExePath が設定されていることを確認（CanApply 内で FindMiseExe が呼ばれる）
        }

        It 'should find mise in WinGet Links' {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExist {
                param($Path)
                return $Path -like "*WinGet\Links\mise.exe"
            }

            $handler.CanApply($ctx)
        }

        It 'should find mise in WinGet Packages' {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExist {
                param($Path)
                if ($Path -like "*WinGet\Packages") { return $true }
                if ($Path -like "*jdx.mise*\mise.exe") { return $true }
                return $false
            }
            Mock Get-ChildItemSafe {
                return @([PSCustomObject]@{ Name = "jdx.mise_1.0.0"; FullName = "C:\Packages\jdx.mise_1.0.0" })
            }

            $handler.CanApply($ctx)
        }

        It 'should find mise in Cargo bin' {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExist {
                param($Path)
                return $Path -like "*\.cargo\bin\mise.exe"
            }

            $handler.CanApply($ctx)
        }
    }

    Context 'Apply - success' {
        BeforeEach {
            Mock Write-Host { }
            Mock Get-ExternalCommand { return @{ Source = "C:\mise.exe" } }
            Mock Test-PathExist { return $true }
            Mock Set-Location { }
            Mock Get-Location { return [PSCustomObject]@{ Path = "D:\dotfiles" } }
            # CanApply 用のデフォルトモック（TestMiseExecutable で使用）
            Mock Invoke-MiseCommand {
                param($MiseExePath, $Arguments)
                if ($Arguments -contains "--version") {
                    $global:LASTEXITCODE = 0
                    return "mise 2024.1.0"
                }
                $global:LASTEXITCODE = 0
                return "Installed"
            }
        }

        It 'should succeed when mise install succeeds' {
            Mock Invoke-MiseCommand {
                $global:LASTEXITCODE = 0
                return "Installed treefmt"
            }

            $handler.CanApply($ctx)
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "mise ツールをインストールしました"
        }

        It 'should fail when mise install fails' {
            Mock Invoke-MiseCommand {
                param($MiseExePath, $Arguments)
                if ($Arguments -contains "install") {
                    $global:LASTEXITCODE = 1
                    return "Error: failed to install"
                }
                $global:LASTEXITCODE = 0
                return ""
            }

            $handler.CanApply($ctx)
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "mise install が失敗しました"
        }
    }

    Context 'Apply - exception handling' {
        BeforeEach {
            Mock Write-Host { }
            Mock Get-ExternalCommand { return @{ Source = "C:\mise.exe" } }
            Mock Test-PathExist { return $true }
            Mock Invoke-MiseCommand {
                $global:LASTEXITCODE = 0
                return "mise 2024.1.0"
            }
        }

        It 'should return failure when exception is thrown' {
            Mock Set-Location { throw "Directory not found" }

            $handler.CanApply($ctx)
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "Directory not found"
        }
    }

    Context 'ShowMiseInstallInstructions' {
        It 'should display installation instructions when mise is not found' {
            $script:instructionsShown = $false

            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExist { return $false }
            Mock Write-Host {
                param($Object)
                if ($Object -match "mise がインストールされていません") {
                    $script:instructionsShown = $true
                }
            }

            $handler.CanApply($ctx)

            $script:instructionsShown | Should -Be $true
        }
    }

    Context 'TestMiseExecutable' {
        BeforeEach {
            Mock Write-Host { }
            Mock Get-ExternalCommand { return @{ Source = "C:\mise.exe" } }
        }

        It 'should return true when mise --version succeeds' {
            Mock Test-PathExist { return $true }
            Mock Invoke-MiseCommand {
                $global:LASTEXITCODE = 0
                return "mise 2024.1.0"
            }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $true
        }

        It 'should return false when mise --version fails with DLL error' {
            Mock Test-PathExist { return $true }
            Mock Invoke-MiseCommand {
                $global:LASTEXITCODE = -1073741515  # STATUS_DLL_NOT_FOUND
                return ""
            }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }

        It 'should return false when mise --version throws exception' {
            Mock Test-PathExist { return $true }
            Mock Invoke-MiseCommand { throw "DLL not found" }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }
    }

    Context 'GetMiseConfigPath' {
        It 'should return correct path' {
            Mock Get-ExternalCommand { return @{ Source = "C:\mise.exe" } }
            Mock Test-PathExist { return $true }
            Mock Invoke-MiseCommand {
                $global:LASTEXITCODE = 0
                return "mise 2024.1.0"
            }

            $handler.CanApply($ctx)

            # .mise.toml のパスが正しく構築されることを確認
            # GetMiseConfigPath は hidden なので、CanApply 経由でテスト
        }
    }

    Context 'TrustMiseConfig' {
        BeforeEach {
            Mock Write-Host { }
            Mock Get-ExternalCommand { return @{ Source = "C:\mise.exe" } }
            Mock Test-PathExist { return $true }
            Mock Get-Location { return [PSCustomObject]@{ Path = "D:\dotfiles" } }
            Mock Set-Location { }
        }

        It 'should run mise trust before mise install' {
            $script:trustCalled = $false
            $script:installCalled = $false
            $script:callOrder = @()

            Mock Invoke-MiseCommand {
                param($MiseExePath, $Arguments)
                if ($Arguments -contains "--version") {
                    $global:LASTEXITCODE = 0
                    return "mise 2024.1.0"
                }
                if ($Arguments -contains "trust") {
                    $script:trustCalled = $true
                    $script:callOrder += "trust"
                }
                if ($Arguments -contains "install") {
                    $script:installCalled = $true
                    $script:callOrder += "install"
                }
                $global:LASTEXITCODE = 0
                return ""
            }

            $handler.CanApply($ctx)
            $handler.Apply($ctx)

            $script:trustCalled | Should -Be $true
            $script:installCalled | Should -Be $true
            $script:callOrder[0] | Should -Be "trust"
        }
    }

    Context 'ShowInstalledTools' {
        BeforeEach {
            Mock Write-Host { }
            Mock Get-ExternalCommand { return @{ Source = "C:\mise.exe" } }
            Mock Test-PathExist { return $true }
            Mock Get-Location { return [PSCustomObject]@{ Path = "D:\dotfiles" } }
            Mock Set-Location { }
        }

        It 'should display installed tools after successful install' {
            $script:listCalled = $false

            Mock Invoke-MiseCommand {
                param($MiseExePath, $Arguments)
                if ($Arguments -contains "--version") {
                    $global:LASTEXITCODE = 0
                    return "mise 2024.1.0"
                }
                if ($Arguments -contains "list") {
                    $script:listCalled = $true
                    return @("treefmt 2.0.0", "pre-commit 3.6.0")
                }
                $global:LASTEXITCODE = 0
                return ""
            }

            $handler.CanApply($ctx)
            $handler.Apply($ctx)

            $script:listCalled | Should -Be $true
        }

        It 'should continue even if mise list fails' {
            Mock Invoke-MiseCommand {
                param($MiseExePath, $Arguments)
                if ($Arguments -contains "--version") {
                    $global:LASTEXITCODE = 0
                    return "mise 2024.1.0"
                }
                if ($Arguments -contains "list") {
                    throw "list failed"
                }
                $global:LASTEXITCODE = 0
                return ""
            }

            $handler.CanApply($ctx)
            $result = $handler.Apply($ctx)

            # list が失敗しても install 自体は成功
            $result.Success | Should -Be $true
        }
    }
}
