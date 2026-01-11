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

    Context 'Constructor' {
        It 'should set <property> to <expected>' -ForEach @(
            @{ property = "Name"; expected = "Chezmoi" }
            @{ property = "Description"; expected = "chezmoi による dotfiles 適用" }
            @{ property = "Order"; expected = 100 }
            @{ property = "RequiresAdmin"; expected = $false }
        ) {
            $handler.$property | Should -Be $expected
        }
    }

    Context 'CanApply - chezmoi detection' {
        It 'should return true when chezmoi is in PATH' {
            Mock Get-ExternalCommand {
                return [PSCustomObject]@{
                    Source = "C:\chezmoi\chezmoi.exe"
                }
            }
            Mock Test-PathExist { return $true }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $true
        }

        It 'should return true when chezmoi is in WinGet Links' {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExist {
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

        It 'should return true when chezmoi is in WinGet Packages' {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExist {
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

        It 'should return true when chezmoi is in Programs directory' {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExist {
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

        It 'should return false and show install instructions when chezmoi is not found' {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExist { return $false }
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

    Context 'CanApply - source directory' {
        It 'should return false when chezmoi source directory does not exist' {
            Mock Get-ExternalCommand {
                return [PSCustomObject]@{ Source = "C:\chezmoi.exe" }
            }
            Mock Test-PathExist {
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

    Context 'Apply - success cases' {
        BeforeEach {
            Mock Get-ExternalCommand {
                return [PSCustomObject]@{ Source = "C:\chezmoi\chezmoi.exe" }
            }
            Mock Test-PathExist { return $true }
            Mock Write-Host { }
        }

        It 'should succeed when chezmoi apply succeeds' {
            Mock Invoke-Chezmoi {
                $global:LASTEXITCODE = 0
            }
            $handler.CanApply($ctx)

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Be "dotfiles を適用しました"
        }

        It 'should pass correct arguments to chezmoi apply' {
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

        It 'should show success message after completion' {
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

    Context 'Apply - failure cases' {
        BeforeEach {
            Mock Get-ExternalCommand {
                return [PSCustomObject]@{ Source = "C:\chezmoi\chezmoi.exe" }
            }
            Mock Test-PathExist { return $true }
            Mock Write-Host { }
        }

        It 'should fail when chezmoi apply fails with non-zero exit code' {
            Mock Invoke-Chezmoi {
                $global:LASTEXITCODE = 1
            }
            $handler.CanApply($ctx)

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "chezmoi apply が失敗しました"
        }

        It 'should show manual execution command on failure' {
            Mock Invoke-Chezmoi {
                $global:LASTEXITCODE = 1
            }
            $handler.CanApply($ctx)

            $handler.Apply($ctx)

            Should -Invoke Write-Host -ParameterFilter {
                $Object -match "手動で実行してください"
            }
        }

        It 'should fail when exception is thrown' {
            Mock Invoke-Chezmoi { throw "chezmoi エラー" }
            $handler.CanApply($ctx)

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "chezmoi エラー"
        }
    }

    Context 'ShowChezmoiInstallInstructions' {
        It 'should include winget command in install instructions' {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExist { return $false }
            Mock Get-ChildItemSafe { return @() }
            Mock Write-Host { }

            $handler.CanApply($ctx)

            Should -Invoke Write-Host -ParameterFilter {
                $Object -match "winget install.*twpayne.chezmoi"
            }
        }

        It 'should include GitHub direct fetch method in install instructions' {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExist { return $false }
            Mock Get-ChildItemSafe { return @() }
            Mock Write-Host { }

            $handler.CanApply($ctx)

            Should -Invoke Write-Host -ParameterFilter {
                $Object -match "chezmoi init rurusasu/dotfiles"
            }
        }

        It 'should include source path in install instructions' {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExist { return $false }
            Mock Get-ChildItemSafe { return @() }
            Mock Write-Host { }

            $handler.CanApply($ctx)

            Should -Invoke Write-Host -ParameterFilter {
                $Object -match "D:\\dotfiles\\chezmoi"
            }
        }
    }

    Context 'FindChezmoiExe - search order' {
        It 'should search in order: PATH, WinGet Links, WinGet Packages, Programs' {
            $script:searchOrder = @()

            Mock Get-ExternalCommand {
                $script:searchOrder += "PATH"
                return $null
            }
            Mock Test-PathExist {
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

        It 'should not search other locations when found in PATH' {
            Mock Get-ExternalCommand {
                return [PSCustomObject]@{ Source = "C:\chezmoi.exe" }
            }
            Mock Test-PathExist { return $true }

            $handler.CanApply($ctx)

            # Test-PathExist は chezmoi ソースディレクトリの確認のみ
            Should -Invoke Test-PathExist -Times 1
        }
    }

    Context 'WinGet Packages search' {
        It 'should search packages with twpayne.chezmoi* pattern' {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExist {
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

        It 'should search next location when chezmoi.exe not found in package' {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExist {
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
