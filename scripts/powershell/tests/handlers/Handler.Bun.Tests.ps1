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

    Context 'CanApply - bun.exe link already exists' {
        BeforeEach {
            Mock Get-ChildItem {
                return [PSCustomObject]@{
                    FullName = "C:\Users\test\AppData\Local\Microsoft\WinGet\Packages\Oven-sh.Bun_Microsoft.Winget.Source_8wekyb3d8bbwe"
                }
            } -ParameterFilter {
                $Path -like "*WinGet\Packages" -and $Filter -like "Oven-sh.Bun_*"
            }

            # bun-windows-x64\bun.exe も Links\bun.exe も存在
            Mock Test-Path { return $true }
            Mock Write-Host { }
        }

        It 'should return false when link exists' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $false
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

            Mock Write-Host { }
        }

        It 'should fallback to copy and return success' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            Should -Invoke Copy-Item -Times 1
        }
    }
}
