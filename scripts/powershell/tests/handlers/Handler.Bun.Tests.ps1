#Requires -Module Pester

<#
.SYNOPSIS
    Handler.Bun.ps1 のユニットテスト

.DESCRIPTION
    BunHandler クラスのテスト
#>

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.Bun.ps1
    $script:projectRoot = (Resolve-Path -LiteralPath "$PSScriptRoot/../../../..").Path
}

Describe 'BunHandler' {
    BeforeEach {
        $script:handler = [BunHandler]::new()
        $script:ctx = [SetupContext]::new($script:projectRoot)
    }

    Context 'Constructor' {
        It 'should set <property> correctly' -ForEach @(
            @{ property = "Name"; expected = "Bun"; checkType = "Be" }
            @{ property = "Description"; expected = $null; checkType = "Not -BeNullOrEmpty" }
            @{ property = "Order"; expected = 8; checkType = "Be" }
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

    Context 'CanApply - Bun not installed' {
        BeforeEach {
            Mock Get-ChildItem { return $null } -ParameterFilter {
                $Path -like "*WinGet\Packages" -and $Filter -like "Oven-sh.Bun_*"
            }
            Mock Write-Host { }
        }

        It 'should return false' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $false
        }
    }

    Context 'CanApply - link exists AND PATH already configured' {
        BeforeEach {
            Mock Get-ChildItem {
                return [PSCustomObject]@{
                    FullName = "C:\Users\test\AppData\Local\Microsoft\WinGet\Packages\Oven-sh.Bun_Microsoft.Winget.Source_8wekyb3d8bbwe"
                }
            } -ParameterFilter {
                $Path -like "*WinGet\Packages" -and $Filter -like "Oven-sh.Bun_*"
            }

            Mock Test-Path { return $true }
            # 実行環境ごとに変わる Links パスを含めて USER PATH を返す
            $script:expectedLinks = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links"
            Mock Get-UserEnvironmentPath { return "C:\Windows;$script:expectedLinks" }
            Mock Write-Host { }
        }

        It 'should return false when both link and PATH are set' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $false
        }
    }

    Context 'CanApply - link exists but PATH not configured' {
        BeforeEach {
            Mock Get-ChildItem {
                return [PSCustomObject]@{
                    FullName = "C:\Users\test\AppData\Local\Microsoft\WinGet\Packages\Oven-sh.Bun_Microsoft.Winget.Source_8wekyb3d8bbwe"
                }
            } -ParameterFilter {
                $Path -like "*WinGet\Packages" -and $Filter -like "Oven-sh.Bun_*"
            }

            Mock Test-Path { return $true }
            # USER PATH に Links が含まれていない状態
            Mock Get-UserEnvironmentPath { return "C:\Windows;C:\Windows\System32" }
            Mock Write-Host { }
        }

        It 'should return true so Apply can add PATH' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $true
        }
    }

    Context 'CanApply - Bun installed but no link' {
        BeforeEach {
            Mock Get-ChildItem {
                return [PSCustomObject]@{
                    FullName = "C:\Users\test\AppData\Local\Microsoft\WinGet\Packages\Oven-sh.Bun_Microsoft.Winget.Source_8wekyb3d8bbwe"
                }
            } -ParameterFilter {
                $Path -like "*WinGet\Packages" -and $Filter -like "Oven-sh.Bun_*"
            }

            Mock Test-Path {
                param($Path)
                if ($Path -like "*bun-windows-x64\bun.exe") { return $true }
                if ($Path -like "*Links\bun.exe") { return $false }
                if ($Path -like "*Links") { return $true }
                return $false
            }
            Mock Get-UserEnvironmentPath { return "" }
            Mock Write-Host { }
        }

        It 'should return true' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $true
        }
    }

    Context 'Apply - executable not found' {
        BeforeEach {
            Mock Get-ChildItem { return $null } -ParameterFilter {
                $Path -like "*WinGet\Packages" -and $Filter -like "Oven-sh.Bun_*"
            }
            Mock Test-Path { return $false }
            Mock Write-Host { }
        }

        It 'should return failure when executable path is null' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $false
            $result.Message | Should -Match "実行ファイルが見つかりません"
        }
    }

    Context 'Apply - creates link successfully' {
        BeforeEach {
            Mock Get-ChildItem {
                return [PSCustomObject]@{
                    FullName = "C:\Users\test\AppData\Local\Microsoft\WinGet\Packages\Oven-sh.Bun_Microsoft.Winget.Source_8wekyb3d8bbwe"
                }
            } -ParameterFilter {
                $Path -like "*WinGet\Packages" -and $Filter -like "Oven-sh.Bun_*"
            }

            Mock Test-Path {
                param($Path)
                if ($Path -like "*bun-windows-x64\bun.exe") { return $true }
                if ($Path -like "*Links") { return $true }
                return $false
            }

            Mock New-Item { } -ParameterFilter { $ItemType -eq "SymbolicLink" }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "HardLink" }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "Directory" }
            Mock Copy-Item { }
            Mock Get-UserEnvironmentPath { return "C:\Windows" }
            Mock Set-UserEnvironmentPath { }

            Mock Write-Host { }
        }

        It 'should return success result' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
        }
    }

    Context 'Apply - fallback to copy when symlink fails' {
        BeforeEach {
            Mock Get-ChildItem {
                return [PSCustomObject]@{
                    FullName = "C:\Users\test\AppData\Local\Microsoft\WinGet\Packages\Oven-sh.Bun_Microsoft.Winget.Source_8wekyb3d8bbwe"
                }
            } -ParameterFilter {
                $Path -like "*WinGet\Packages" -and $Filter -like "Oven-sh.Bun_*"
            }

            Mock Test-Path {
                param($Path)
                if ($Path -like "*bun-windows-x64\bun.exe") { return $true }
                if ($Path -like "*Links") { return $true }
                return $false
            }

            Mock New-Item { throw "Administrator privilege required" } -ParameterFilter {
                $ItemType -eq "SymbolicLink" -or $ItemType -eq "HardLink"
            }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "Directory" }

            Mock Copy-Item { }
            Mock Get-UserEnvironmentPath { return "C:\Windows" }
            Mock Set-UserEnvironmentPath { }

            Mock Write-Host { }
        }

        It 'should fallback to copy and return success' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            Should -Invoke Copy-Item -Times 1
        }
    }

    Context 'Apply - link exists but PATH missing (recovers from previous partial run)' {
        BeforeEach {
            Mock Get-ChildItem {
                return [PSCustomObject]@{
                    FullName = "C:\Users\test\AppData\Local\Microsoft\WinGet\Packages\Oven-sh.Bun_Microsoft.Winget.Source_8wekyb3d8bbwe"
                }
            } -ParameterFilter {
                $Path -like "*WinGet\Packages" -and $Filter -like "Oven-sh.Bun_*"
            }

            # link はすでに存在するが PATH に含まれていない状態を再現
            Mock Test-Path { return $true }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "Directory" }
            Mock New-Item { throw "should not be called when link exists" } -ParameterFilter {
                $ItemType -eq "SymbolicLink" -or $ItemType -eq "HardLink"
            }
            Mock Copy-Item { }
            Mock Get-UserEnvironmentPath { return "C:\Windows;C:\Windows\System32" }
            Mock Set-UserEnvironmentPath { }

            Mock Write-Host { }
        }

        It 'should add Links to PATH without recreating the link' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            Should -Invoke Set-UserEnvironmentPath -Times 1
            Should -Invoke Copy-Item -Times 0
            Should -Invoke New-Item -Times 0 -ParameterFilter { $ItemType -eq "SymbolicLink" -or $ItemType -eq "HardLink" }
        }
    }
}
