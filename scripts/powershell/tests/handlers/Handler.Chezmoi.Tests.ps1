#Requires -Module Pester

<#
.SYNOPSIS
    Handler.Chezmoi.ps1 のユニットテスト

.DESCRIPTION
    ChezmoiHandler クラスのテスト
    100% カバレッジを目標とする
#>

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.Chezmoi.ps1
}

Describe 'ChezmoiHandler' {
    BeforeEach {
        $script:handler = [ChezmoiHandler]::new()
        $script:ctx = [SetupContext]::new("D:\dotfiles")
    }

    Context 'コンストラクタ' {
        It 'Name が Chezmoi に設定される' {
            $handler.Name | Should -Be "Chezmoi"
        }

        It 'Description が設定される' {
            $handler.Description | Should -Be "chezmoi による dotfiles 適用"
        }

        It 'Order が 100 に設定される' {
            $handler.Order | Should -Be 100
        }

        It 'RequiresAdmin が $false に設定される' {
            $handler.RequiresAdmin | Should -Be $false
        }
    }

    Context 'CanApply - chezmoi 検出' {
        It 'chezmoi が PATH にある場合は $true' {
            Mock Get-ExternalCommand { 
                return [PSCustomObject]@{ 
                    Source = "C:\chezmoi\chezmoi.exe" 
                }
            }
            Mock Test-PathExists { return $true }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $true
        }

        It 'chezmoi が WinGet Links にある場合は $true' {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExists { 
                param($Path)
                # WinGet Links の chezmoi.exe が存在
                if ($Path -like "*WinGet\Links\chezmoi.exe") { return $true }
                # ソースディレクトリも存在
                if ($Path -like "*chezmoi") { return $true }
                return $false
            }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $true
        }

        It 'chezmoi が WinGet Packages にある場合は $true' {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExists { 
                param($Path)
                if ($Path -like "*WinGet\Links*") { return $false }
                if ($Path -like "*WinGet\Packages") { return $true }
                if ($Path -like "*chezmoi.exe") { return $true }
                if ($Path -like "*chezmoi") { return $true }  # ソースディレクトリ
                return $false
            }
            Mock Get-ChildItemSafe { 
                return @([PSCustomObject]@{ 
                    Name = "twpayne.chezmoi_1.0.0"
                    FullName = "C:\WinGet\Packages\twpayne.chezmoi_1.0.0"
                })
            }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $true
        }

        It 'chezmoi が Programs ディレクトリにある場合は $true' {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExists { 
                param($Path)
                if ($Path -like "*WinGet\Links*") { return $false }
                if ($Path -like "*WinGet\Packages") { return $false }
                if ($Path -like "*Programs\chezmoi\chezmoi.exe") { return $true }
                if ($Path -like "*chezmoi") { return $true }  # ソースディレクトリ
                return $false
            }
            Mock Get-ChildItemSafe { return @() }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $true
        }

        It 'chezmoi が見つからない場合はインストール手順を表示して $false' {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExists { return $false }
            Mock Get-ChildItemSafe { return @() }
            $script:notFoundMessageShown = $false
            Mock Write-Host { 
                param($Object)
                if ($Object -match "chezmoi がインストールされていません") {
                    $script:notFoundMessageShown = $true
                }
            }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
            $script:notFoundMessageShown | Should -Be $true
        }
    }

    Context 'CanApply - ソースディレクトリ' {
        It 'chezmoi ソースディレクトリが存在しない場合は $false' {
            Mock Get-ExternalCommand { 
                return [PSCustomObject]@{ Source = "C:\chezmoi.exe" }
            }
            Mock Test-PathExists { 
                param($Path)
                if ($Path -like "*chezmoi.exe") { return $true }
                return $false  # ソースディレクトリは存在しない
            }
            $script:sourceDirNotFoundShown = $false
            Mock Write-Host { 
                param($Object)
                if ($Object -match "ソースディレクトリが見つかりません") {
                    $script:sourceDirNotFoundShown = $true
                }
            }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
            $script:sourceDirNotFoundShown | Should -Be $true
        }
    }

    Context 'Apply - 正常系' {
        BeforeEach {
            Mock Get-ExternalCommand { 
                return [PSCustomObject]@{ Source = "C:\chezmoi\chezmoi.exe" }
            }
            Mock Test-PathExists { return $true }
            Mock Write-Host { }
        }

        It 'chezmoi apply が成功した場合' {
            Mock Invoke-Chezmoi { 
                $global:LASTEXITCODE = 0
            }
            $handler.CanApply($ctx)

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Be "dotfiles を適用しました"
        }

        It 'chezmoi apply に正しい引数が渡される' {
            $script:chezmoiArgs = ""
            $script:chezmoiExePath = ""
            Mock Invoke-Chezmoi { 
                param($ExePath, $Arguments)
                $script:chezmoiExePath = $ExePath
                $script:chezmoiArgs = $Arguments -join " "
                $global:LASTEXITCODE = 0
            }
            $handler.CanApply($ctx)

            $handler.Apply($ctx)

            $script:chezmoiExePath | Should -Be "C:\chezmoi\chezmoi.exe"
            $script:chezmoiArgs | Should -Match "--source.*D:\\dotfiles\\chezmoi.*apply"
        }

        It '成功後にメッセージが表示される' {
            $script:successMessageShown = $false
            Mock Invoke-Chezmoi { 
                $global:LASTEXITCODE = 0
            }
            Mock Write-Host { 
                param($Object, $ForegroundColor)
                if ($Object -match "chezmoi apply 完了" -and $ForegroundColor -eq "Green") {
                    $script:successMessageShown = $true
                }
            }
            $handler.CanApply($ctx)

            $handler.Apply($ctx)

            $script:successMessageShown | Should -Be $true
        }
    }

    Context 'Apply - 失敗系' {
        BeforeEach {
            Mock Get-ExternalCommand { 
                return [PSCustomObject]@{ Source = "C:\chezmoi\chezmoi.exe" }
            }
            Mock Test-PathExists { return $true }
            Mock Write-Host { }
        }

        It 'chezmoi apply が失敗した場合（exit code != 0）' {
            Mock Invoke-Chezmoi { 
                $global:LASTEXITCODE = 1
            }
            $handler.CanApply($ctx)

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "chezmoi apply が失敗しました"
        }

        It '失敗時に手動実行コマンドが表示される' {
            Mock Invoke-Chezmoi { 
                $global:LASTEXITCODE = 1
            }
            $handler.CanApply($ctx)

            $handler.Apply($ctx)

            Should -Invoke Write-Host -ParameterFilter {
                $Object -match "手動で実行してください"
            }
        }

        It '例外が発生した場合' {
            Mock Invoke-Chezmoi { throw "chezmoi エラー" }
            $handler.CanApply($ctx)

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "chezmoi エラー"
        }
    }

    Context 'ShowChezmoiInstallInstructions' {
        It 'インストール手順に winget コマンドが含まれる' {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExists { return $false }
            Mock Get-ChildItemSafe { return @() }
            Mock Write-Host { }

            $handler.CanApply($ctx)

            Should -Invoke Write-Host -ParameterFilter {
                $Object -match "winget install.*twpayne.chezmoi"
            }
        }

        It 'インストール手順に GitHub 直接取得方法が含まれる' {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExists { return $false }
            Mock Get-ChildItemSafe { return @() }
            Mock Write-Host { }

            $handler.CanApply($ctx)

            Should -Invoke Write-Host -ParameterFilter {
                $Object -match "chezmoi init rurusasu/dotfiles"
            }
        }

        It 'インストール手順にソースパスが含まれる' {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExists { return $false }
            Mock Get-ChildItemSafe { return @() }
            Mock Write-Host { }

            $handler.CanApply($ctx)

            Should -Invoke Write-Host -ParameterFilter {
                $Object -match "D:\\dotfiles\\chezmoi"
            }
        }
    }

    Context 'FindChezmoiExe - 検索順序' {
        It 'PATH → WinGet Links → WinGet Packages → Programs の順で検索する' {
            $script:searchOrder = @()
            
            Mock Get-ExternalCommand { 
                $script:searchOrder += "PATH"
                return $null
            }
            Mock Test-PathExists { 
                param($Path)
                if ($Path -like "*WinGet\Links*") {
                    $script:searchOrder += "Links"
                    return $false
                }
                if ($Path -like "*WinGet\Packages") {
                    $script:searchOrder += "Packages"
                    return $false
                }
                if ($Path -like "*Programs\chezmoi*") {
                    $script:searchOrder += "Programs"
                    return $false
                }
                return $false
            }
            Mock Get-ChildItemSafe { return @() }
            Mock Write-Host { }

            $handler.CanApply($ctx)

            $script:searchOrder[0] | Should -Be "PATH"
            $script:searchOrder | Should -Contain "Links"
            $script:searchOrder | Should -Contain "Packages"
        }

        It 'PATH で見つかった場合は他を検索しない' {
            Mock Get-ExternalCommand { 
                return [PSCustomObject]@{ Source = "C:\chezmoi.exe" }
            }
            Mock Test-PathExists { return $true }

            $handler.CanApply($ctx)

            # Test-PathExists は chezmoi ソースディレクトリの確認のみ
            Should -Invoke Test-PathExists -Times 1
        }
    }

    Context 'WinGet Packages 検索' {
        It 'twpayne.chezmoi* パターンでパッケージを検索する' {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExists { 
                param($Path)
                if ($Path -like "*WinGet\Links*") { return $false }
                if ($Path -like "*WinGet\Packages") { return $true }
                if ($Path -like "*twpayne.chezmoi*\chezmoi.exe") { return $true }
                if ($Path -like "*chezmoi") { return $true }
                return $false
            }
            Mock Get-ChildItemSafe { 
                param($Path)
                if ($Path -like "*Packages*") {
                    return @([PSCustomObject]@{ 
                        Name = "twpayne.chezmoi_2.40.0_x64"
                        FullName = "C:\WinGet\Packages\twpayne.chezmoi_2.40.0_x64"
                    })
                }
                return @()
            }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $true
            Should -Invoke Get-ChildItemSafe -ParameterFilter {
                $Directory -eq $true
            }
        }

        It 'パッケージ内に chezmoi.exe がない場合は次を検索する' {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExists { 
                param($Path)
                if ($Path -like "*WinGet\Links*") { return $false }
                if ($Path -like "*WinGet\Packages") { return $true }
                if ($Path -like "*twpayne.chezmoi*\chezmoi.exe") { return $false }
                if ($Path -like "*Programs\chezmoi*") { return $true }
                if ($Path -like "*chezmoi") { return $true }
                return $false
            }
            Mock Get-ChildItemSafe { 
                return @([PSCustomObject]@{ 
                    Name = "twpayne.chezmoi_2.40.0"
                    FullName = "C:\WinGet\Packages\twpayne.chezmoi_2.40.0"
                })
            }

            $result = $handler.CanApply($ctx)

            # Programs で見つかる
            $result | Should -Be $true
        }
    }
}
