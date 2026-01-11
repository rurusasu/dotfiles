#Requires -Module Pester

<#
.SYNOPSIS
    Handler.NixOSWSL.ps1 のユニットテスト

.DESCRIPTION
    NixOSWSLHandler クラスのテスト
    環境依存のテストはスキップし、ロジックのテストに集中
#>

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.NixOSWSL.ps1
}

Describe 'NixOSWSLHandler' {
    BeforeEach {
        $script:handler = [NixOSWSLHandler]::new()
        $script:ctx = [SetupContext]::new("D:\dotfiles")
        $script:ctx.DistroName = "NixOS"
        $script:ctx.InstallDir = "D:\WSL\NixOS"
    }

    Context 'Constructor' {
        It 'should set <property> to <expected>' -ForEach @(
            @{ property = "Name"; expected = "NixOSWSL" }
            @{ property = "Description"; expected = "NixOS-WSL のダウンロードとインストール" }
            @{ property = "Order"; expected = 50 }
            @{ property = "RequiresAdmin"; expected = $true }
        ) {
            $handler.$property | Should -Be $expected
        }
    }

    Context 'CanApply' {
        It 'should return true when distro does not exist' {
            # DistroExists が $false を返すようにモック
            $handler | Add-Member -MemberType ScriptMethod -Name DistroExists -Value { return $false } -Force
            Mock Write-Host { }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $true
        }

        It 'should return false when distro already exists' {
            # DistroExists が $true を返すようにモック
            $handler | Add-Member -MemberType ScriptMethod -Name DistroExists -Value { return $true } -Force
            Mock Write-Host { }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }
    }

    Context 'Apply - success path' {
        BeforeEach {
            # すべての依存関数をモック
            $handler | Add-Member -MemberType ScriptMethod -Name AssertAdmin -Value { } -Force
            $handler | Add-Member -MemberType ScriptMethod -Name EnsureWslReady -Value { } -Force
            $handler | Add-Member -MemberType ScriptMethod -Name GetRelease -Value {
                return @{ tag_name = "v24.5.1"; assets = @() }
            } -Force
            $handler | Add-Member -MemberType ScriptMethod -Name SelectAsset -Value {
                return @{ name = "nixos.wsl"; browser_download_url = "http://example.com/nixos.wsl" }
            } -Force
            $handler | Add-Member -MemberType ScriptMethod -Name DownloadAsset -Value {
                return "C:\Temp\nixos.wsl"
            } -Force
            $handler | Add-Member -MemberType ScriptMethod -Name InstallDistro -Value { } -Force
            $handler | Add-Member -MemberType ScriptMethod -Name ExecutePostInstall -Value { } -Force
            $handler | Add-Member -MemberType ScriptMethod -Name EnsureWhoamiShim -Value { } -Force
            $handler | Add-Member -MemberType ScriptMethod -Name EnsureWslWritable -Value { } -Force
            Mock Write-Host { }
        }

        It 'should return success result' {
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "NixOS-WSL のインストールが完了しました"
        }
    }

    Context 'Apply - error handling' {
        It 'should return failure result when exception occurs' {
            $handler | Add-Member -MemberType ScriptMethod -Name AssertAdmin -Value {
                throw "管理者権限がありません"
            } -Force
            Mock Write-Host { }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "管理者権限がありません"
        }
    }

    Context 'AssertAdmin' {
        It 'should throw exception when not running as administrator' {
            Mock New-Object {
                $principal = [PSCustomObject]@{}
                $principal | Add-Member -MemberType ScriptMethod -Name IsInRole -Value { return $false }
                return $principal
            } -ParameterFilter { $TypeName -eq 'Security.Principal.WindowsPrincipal' }

            { $handler.AssertAdmin() } | Should -Throw "このハンドラーは管理者権限が必要です"
        }
    }

    Context 'SupportsFromFileInstall' {
        It 'should return true when WSL version is 2.4.4+' {
            $handler | Add-Member -MemberType ScriptMethod -Name GetWslVersion -Value {
                return [version]"2.4.4.0"
            } -Force

            $result = $handler.SupportsFromFileInstall()

            $result | Should -Be $true
        }

        It 'should check help text when WSL version is below 2.4.4' {
            $handler | Add-Member -MemberType ScriptMethod -Name GetWslVersion -Value {
                return [version]"2.0.0.0"
            } -Force

            $result = $handler.SupportsFromFileInstall()

            # 実際の環境依存のため、結果は bool であることのみを確認
            $result | Should -BeOfType [bool]
        }
    }

    Context 'GetRelease' {
        It 'should fetch latest release from GitHub API' {
            Mock Invoke-RestMethod {
                return @{
                    tag_name = "v24.5.1"
                    assets = @()
                }
            }
            Mock Write-Host { }

            $result = $handler.GetRelease("")

            $result.tag_name | Should -Be "v24.5.1"
            Should -Invoke Invoke-RestMethod -ParameterFilter {
                $Uri -match "/releases/latest"
            }
        }

        It 'should fetch specific tag when specified' {
            Mock Invoke-RestMethod {
                return @{
                    tag_name = "v24.5.0"
                    assets = @()
                }
            }
            Mock Write-Host { }

            $result = $handler.GetRelease("v24.5.0")

            Should -Invoke Invoke-RestMethod -ParameterFilter {
                $Uri -match "/releases/tags/v24.5.0"
            }
        }
    }

    Context 'SelectAsset' {
        It 'should prefer nixos.wsl asset' {
            $release = @{
                assets = @(
                    @{ name = "nixos-wsl.tar.gz" },
                    @{ name = "nixos.wsl" }
                )
            }
            Mock Write-Host { }

            $result = $handler.SelectAsset($release)

            $result.name | Should -Be "nixos.wsl"
        }

        It 'should select nixos-wsl.tar.gz when nixos.wsl is not available' {
            $release = @{
                assets = @(
                    @{ name = "nixos-wsl.tar.gz" },
                    @{ name = "other.txt" }
                )
            }
            Mock Write-Host { }

            $result = $handler.SelectAsset($release)

            $result.name | Should -Be "nixos-wsl.tar.gz"
        }

        It 'should throw exception when no asset is found' {
            $release = @{
                tag_name = "v1.0.0"
                assets = @()
            }

            { $handler.SelectAsset($release) } | Should -Throw "*利用可能なアーカイブが見つかりません*"
        }
    }

    Context 'DownloadAsset' {
        It 'should download asset' {
            $asset = @{
                name = "nixos.wsl"
                browser_download_url = "http://example.com/nixos.wsl"
            }
            Mock Invoke-WebRequest { }
            Mock Write-Host { }

            $result = $handler.DownloadAsset($asset)

            $result | Should -Match "nixos.wsl"
            Should -Invoke Invoke-WebRequest -ParameterFilter {
                $Uri -eq "http://example.com/nixos.wsl"
            }
        }
    }

    Context 'EnsureInstallDir' {
        It 'should create directory when it does not exist' {
            Mock Test-Path { return $false }
            Mock New-Item { }

            { $handler.EnsureInstallDir("C:\Test") } | Should -Not -Throw

            Should -Invoke New-Item -ParameterFilter {
                $ItemType -eq "Directory"
            }
        }

        It 'should throw exception when directory is not empty' {
            Mock Test-Path { return $true } -ParameterFilter { $PathType -eq 'Container' }
            Mock Test-Path { return $true } -ParameterFilter { -not $PSBoundParameters.ContainsKey('PathType') }
            Mock Get-ChildItem {
                return @([PSCustomObject]@{ Name = "file.txt" })
            }

            { $handler.EnsureInstallDir("C:\Test") } | Should -Throw "*空ではありません*"
        }
    }

    Context 'InstallDistro' {
        BeforeEach {
            $asset = @{ name = "nixos.wsl" }
            $handler | Add-Member -MemberType ScriptMethod -Name SupportsFromFileInstall -Value { return $true } -Force
        }

        It 'should use InstallFromFile for .wsl file' {
            $script:callCount = 0
            $handler | Add-Member -MemberType ScriptMethod -Name InstallFromFile -Value { $script:callCount++ } -Force

            $handler.InstallDistro($ctx, $asset, "C:\Temp\nixos.wsl")

            $script:callCount | Should -Be 1
        }

        It 'should fallback to ImportDistro when InstallFromFile fails' {
            $handler | Add-Member -MemberType ScriptMethod -Name InstallFromFile -Value {
                throw "Failed"
            } -Force
            $script:callCount = 0
            $handler | Add-Member -MemberType ScriptMethod -Name ImportDistro -Value { $script:callCount++ } -Force
            Mock Write-Host { }

            $handler.InstallDistro($ctx, $asset, "C:\Temp\nixos.wsl")

            $script:callCount | Should -Be 1
        }
    }

    Context 'ExecutePostInstall' {
        It 'should skip when SkipPostInstallSetup is true' {
            $ctx.Options["SkipPostInstallSetup"] = $true
            Mock Write-Host { }

            { $handler.ExecutePostInstall($ctx) } | Should -Not -Throw
        }

        It 'should show warning when script does not exist' {
            $ctx.Options["PostInstallScript"] = "C:\NonExistent\script.sh"
            Mock Test-Path { return $false }
            Mock Write-Host { }

            { $handler.ExecutePostInstall($ctx) } | Should -Not -Throw
        }
    }
}
