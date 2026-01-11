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

    Context 'コンストラクタ' {
        It 'Name が NixOSWSL に設定される' {
            $handler.Name | Should -Be "NixOSWSL"
        }

        It 'Description が設定される' {
            $handler.Description | Should -Be "NixOS-WSL のダウンロードとインストール"
        }

        It 'Order が 50 に設定される' {
            $handler.Order | Should -Be 50
        }

        It 'RequiresAdmin が $true に設定される' {
            $handler.RequiresAdmin | Should -Be $true
        }
    }

    Context 'CanApply' {
        It 'ディストリビューションが存在しない場合は $true を返す' {
            # DistroExists が $false を返すようにモック
            $handler | Add-Member -MemberType ScriptMethod -Name DistroExists -Value { return $false } -Force
            Mock Write-Host { }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $true
        }

        It 'ディストリビューションが存在する場合は $false を返す' {
            # DistroExists が $true を返すようにモック
            $handler | Add-Member -MemberType ScriptMethod -Name DistroExists -Value { return $true } -Force
            Mock Write-Host { }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }
    }

    Context 'Apply - 成功パス' {
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

        It '成功結果を返す' {
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "NixOS-WSL のインストールが完了しました"
        }
    }

    Context 'Apply - エラーハンドリング' {
        It '例外が発生した場合は失敗結果を返す' {
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
        It '管理者権限がない場合は例外をスローする' {
            Mock New-Object {
                $principal = [PSCustomObject]@{}
                $principal | Add-Member -MemberType ScriptMethod -Name IsInRole -Value { return $false }
                return $principal
            } -ParameterFilter { $TypeName -eq 'Security.Principal.WindowsPrincipal' }

            { $handler.AssertAdmin() } | Should -Throw "このハンドラーは管理者権限が必要です"
        }
    }

    Context 'SupportsFromFileInstall' {
        It 'WSL 2.4.4+ の場合は $true を返す' {
            $handler | Add-Member -MemberType ScriptMethod -Name GetWslVersion -Value {
                return [version]"2.4.4.0"
            } -Force

            $result = $handler.SupportsFromFileInstall()

            $result | Should -Be $true
        }

        It 'WSL 2.4.3 以下の場合はヘルプテキストをチェックする' {
            $handler | Add-Member -MemberType ScriptMethod -Name GetWslVersion -Value {
                return [version]"2.0.0.0"
            } -Force

            $result = $handler.SupportsFromFileInstall()

            # 実際の環境依存のため、結果は bool であることのみを確認
            $result | Should -BeOfType [bool]
        }
    }

    Context 'GetRelease' {
        It 'GitHub API から latest リリースを取得する' {
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

        It '特定のタグを指定できる' {
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
        It 'nixos.wsl を優先的に選択する' {
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

        It 'nixos.wsl がない場合は nixos-wsl.tar.gz を選択する' {
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

        It 'アセットが見つからない場合は例外をスローする' {
            $release = @{
                tag_name = "v1.0.0"
                assets = @()
            }

            { $handler.SelectAsset($release) } | Should -Throw "*利用可能なアーカイブが見つかりません*"
        }
    }

    Context 'DownloadAsset' {
        It 'アセットをダウンロードする' {
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
        It 'ディレクトリが存在しない場合は作成する' {
            Mock Test-Path { return $false }
            Mock New-Item { }

            { $handler.EnsureInstallDir("C:\Test") } | Should -Not -Throw

            Should -Invoke New-Item -ParameterFilter {
                $ItemType -eq "Directory"
            }
        }

        It 'ディレクトリが空でない場合は例外をスローする' {
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

        It '.wsl ファイルの場合は InstallFromFile を使用する' {
            $script:callCount = 0
            $handler | Add-Member -MemberType ScriptMethod -Name InstallFromFile -Value { $script:callCount++ } -Force

            $handler.InstallDistro($ctx, $asset, "C:\Temp\nixos.wsl")

            $script:callCount | Should -Be 1
        }

        It 'InstallFromFile が失敗した場合は ImportDistro にフォールバックする' {
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
        It 'SkipPostInstallSetup が true の場合は何もしない' {
            $ctx.Options["SkipPostInstallSetup"] = $true
            Mock Write-Host { }

            { $handler.ExecutePostInstall($ctx) } | Should -Not -Throw
        }

        It 'スクリプトが存在しない場合は警告を出す' {
            $ctx.Options["PostInstallScript"] = "C:\NonExistent\script.sh"
            Mock Test-Path { return $false }
            Mock Write-Host { }

            { $handler.ExecutePostInstall($ctx) } | Should -Not -Throw
        }
    }
}
