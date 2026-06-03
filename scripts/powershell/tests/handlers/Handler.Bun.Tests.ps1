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

    # GetBunExecutablePath() が返すパス（パッケージ dir + サブディレクトリ + 実行ファイル）
    $script:bunPkgDir = "C:\Users\test\AppData\Local\Microsoft\WinGet\Packages\Oven-sh.Bun_Microsoft.Winget.Source_8wekyb3d8bbwe"
    $script:bunExe = Join-Path $script:bunPkgDir "bun-windows-x64\bun.exe"

    function script:Set-BunPackageInstalled {
        Mock Get-ChildItem {
            return [PSCustomObject]@{ FullName = $script:bunPkgDir }
        } -ParameterFilter {
            $Path -like "*WinGet\Packages" -and $Filter -like "Oven-sh.Bun_*"
        }
    }
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

    Context 'CanApply - link is current AND PATH already configured' {
        BeforeEach {
            Set-BunPackageInstalled
            Mock Test-Path {
                if ($Path -like "*bun-windows-x64\bun.exe") { return $true }
                if ($LiteralPath -like "*Links\bun.exe") { return $true }
                return $false
            }
            Mock Get-Item {
                return [PSCustomObject]@{ LinkType = "SymbolicLink"; Target = $script:bunExe }
            } -ParameterFilter { $LiteralPath -like "*Links\bun.exe" }
            $script:expectedLinks = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links"
            Mock Get-UserEnvironmentPath { return "C:\Windows;$script:expectedLinks" }
            Mock Write-Host { }
        }

        It 'should return false when both link and PATH are set' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $false
        }
    }

    Context 'CanApply - link is stale copy from old version (winget upgrade)' {
        BeforeEach {
            Set-BunPackageInstalled
            Mock Test-Path {
                if ($Path -like "*bun-windows-x64\bun.exe") { return $true }
                if ($LiteralPath -like "*Links\bun.exe") { return $true }
                return $false
            }
            Mock Get-Item {
                if ($LiteralPath -like "*Links\bun.exe") {
                    return [PSCustomObject]@{ LinkType = ""; Length = 100; LastWriteTimeUtc = [datetime]'2024-01-01' }
                }
                return [PSCustomObject]@{ LinkType = ""; Length = 200; LastWriteTimeUtc = [datetime]'2024-06-01' }
            }
            $script:expectedLinks = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links"
            Mock Get-UserEnvironmentPath { return "C:\Windows;$script:expectedLinks" }
            Mock Write-Host { }
        }

        It 'should return true so the stale link is refreshed' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $true
        }
    }

    Context 'CanApply - link is current but PATH not configured' {
        BeforeEach {
            Set-BunPackageInstalled
            Mock Test-Path {
                if ($Path -like "*bun-windows-x64\bun.exe") { return $true }
                if ($LiteralPath -like "*Links\bun.exe") { return $true }
                return $false
            }
            Mock Get-Item {
                return [PSCustomObject]@{ LinkType = "SymbolicLink"; Target = $script:bunExe }
            } -ParameterFilter { $LiteralPath -like "*Links\bun.exe" }
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
            Set-BunPackageInstalled
            Mock Test-Path {
                if ($Path -like "*bun-windows-x64\bun.exe") { return $true }
                if ($LiteralPath -like "*Links\bun.exe") { return $false }
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

    Context 'Apply - creates link when missing' {
        BeforeEach {
            Set-BunPackageInstalled
            Mock Test-Path {
                if ($Path -like "*bun-windows-x64\bun.exe") { return $true }
                if ($Path -like "*Links") { return $true }
                if ($LiteralPath -like "*Links\bun.exe") { return $false }
                return $false
            }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "SymbolicLink" }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "HardLink" }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "Directory" }
            Mock Remove-Item { }
            Mock Copy-Item { }
            Mock Get-UserEnvironmentPath { return "C:\Windows" }
            Mock Set-UserEnvironmentPath { }
            Mock Write-Host { }
        }

        It 'should create symlink and return success' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            Should -Invoke New-Item -Times 1 -ParameterFilter { $ItemType -eq "SymbolicLink" }
        }
    }

    Context 'Apply - fallback to copy when symlink fails' {
        BeforeEach {
            Set-BunPackageInstalled
            Mock Test-Path {
                if ($Path -like "*bun-windows-x64\bun.exe") { return $true }
                if ($Path -like "*Links") { return $true }
                if ($LiteralPath -like "*Links\bun.exe") { return $false }
                return $false
            }
            Mock New-Item { throw "Administrator privilege required" } -ParameterFilter {
                $ItemType -eq "SymbolicLink" -or $ItemType -eq "HardLink"
            }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "Directory" }
            Mock Remove-Item { }
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

    Context 'Apply - refreshes stale link after winget upgrade' {
        BeforeEach {
            Set-BunPackageInstalled
            Mock Test-Path {
                if ($Path -like "*bun-windows-x64\bun.exe") { return $true }
                if ($Path -like "*Links") { return $true }
                if ($LiteralPath -like "*Links\bun.exe") { return $true }
                return $false
            }
            Mock Get-Item {
                if ($LiteralPath -like "*Links\bun.exe") {
                    return [PSCustomObject]@{ LinkType = ""; Length = 100; LastWriteTimeUtc = [datetime]'2024-01-01' }
                }
                return [PSCustomObject]@{ LinkType = ""; Length = 200; LastWriteTimeUtc = [datetime]'2024-06-01' }
            }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "SymbolicLink" }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "Directory" }
            Mock Remove-Item { }
            Mock Copy-Item { }
            $script:expectedLinks = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links"
            Mock Get-UserEnvironmentPath { return "C:\Windows;$script:expectedLinks" }
            Mock Set-UserEnvironmentPath { }
            Mock Write-Host { }
        }

        It 'should remove the stale link and recreate it' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            Should -Invoke Remove-Item -Times 1 -ParameterFilter { $LiteralPath -like "*Links\bun.exe" }
            Should -Invoke New-Item -Times 1 -ParameterFilter { $ItemType -eq "SymbolicLink" }
        }
    }

    Context 'Apply - link current but PATH missing (recovers from previous partial run)' {
        BeforeEach {
            Set-BunPackageInstalled
            Mock Test-Path {
                if ($Path -like "*bun-windows-x64\bun.exe") { return $true }
                if ($Path -like "*Links") { return $true }
                if ($LiteralPath -like "*Links\bun.exe") { return $true }
                return $false
            }
            # 現行 exe を指すシンボリックリンク（最新）
            Mock Get-Item {
                return [PSCustomObject]@{ LinkType = "SymbolicLink"; Target = $script:bunExe }
            } -ParameterFilter { $LiteralPath -like "*Links\bun.exe" }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "Directory" }
            Mock New-Item { throw "should not recreate a current link" } -ParameterFilter {
                $ItemType -eq "SymbolicLink" -or $ItemType -eq "HardLink"
            }
            Mock Remove-Item { }
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
