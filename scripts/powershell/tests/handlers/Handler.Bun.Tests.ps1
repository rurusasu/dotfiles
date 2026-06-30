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

    Context 'CanApply - executable directory PATH already configured' {
        BeforeEach {
            Set-BunPackageInstalled
            Mock Test-Path {
                if ($Path -like "*bun-windows-x64\bun.exe") { return $true }
                if ($LiteralPath -like "*Links\bun.exe") { return $false }
                return $false
            }
            $script:bunBinDir = Split-Path -Parent $script:bunExe
            Mock Get-UserEnvironmentPath { return "C:\Windows;$script:bunBinDir" }
            Mock Write-Host { }
        }

        It 'should return false without requiring a WinGet Links shim' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $false
        }
    }

    Context 'CanApply - legacy shim is stale copy from old version (winget upgrade)' {
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

        It 'should return true so the stale shim is removed' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $true
        }
    }

    Context 'CanApply - legacy shim exists but PATH not configured' {
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

        It 'should return true so Apply can remove the shim and add PATH' {
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

    Context 'CanApply - Bun executable directory is already on PATH' {
        BeforeEach {
            Set-BunPackageInstalled
            Mock Test-Path {
                if ($Path -like "*bun-windows-x64\bun.exe") { return $true }
                if ($LiteralPath -like "*Links\bun.exe") { return $false }
                return $false
            }
            $script:bunBinDir = Split-Path -Parent $script:bunExe
            Mock Get-UserEnvironmentPath { return "C:\Windows;$script:bunBinDir" }
            Mock Write-Host { }
        }

        It 'should return false without requiring a WinGet Links shim' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $false
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

    Context 'Apply - adds executable directory when PATH is missing' {
        BeforeEach {
            Set-BunPackageInstalled
            $script:bunBinDir = Split-Path -Parent $script:bunExe
            Mock Test-Path {
                if ($Path -like "*bun-windows-x64\bun.exe") { return $true }
                if ($Path -like "*Links") { return $true }
                if ($LiteralPath -like "*Links\bun.exe") { return $false }
                return $false
            }
            Mock New-Item { throw "Bun should not create shims" } -ParameterFilter {
                $ItemType -eq "SymbolicLink" -or $ItemType -eq "HardLink"
            }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "Directory" }
            Mock Remove-Item { }
            Mock Copy-Item { throw "Bun should not copy shims" }
            Mock Get-UserEnvironmentPath { return "C:\Windows" }
            Mock Set-UserEnvironmentPath { }
            Mock Write-Host { }
        }

        It 'should add bun-windows-x64 to PATH without creating a shim' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            Should -Invoke Set-UserEnvironmentPath -Times 1 -ParameterFilter { $Path -like "*$script:bunBinDir*" }
            Should -Invoke New-Item -Times 0 -ParameterFilter { $ItemType -eq "SymbolicLink" -or $ItemType -eq "HardLink" }
            Should -Invoke Copy-Item -Times 0
        }
    }

    Context 'Apply - no copy fallback when PATH is missing' {
        BeforeEach {
            Set-BunPackageInstalled
            $script:bunBinDir = Split-Path -Parent $script:bunExe
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

        It 'should add PATH directly and never copy a command shim' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            Should -Invoke Set-UserEnvironmentPath -Times 1 -ParameterFilter { $Path -like "*$script:bunBinDir*" }
            Should -Invoke Copy-Item -Times 0
        }
    }

    Context 'Apply - direct executable directory PATH' {
        BeforeEach {
            Set-BunPackageInstalled
            $script:bunBinDir = Split-Path -Parent $script:bunExe
            Mock Test-Path {
                if ($Path -like "*bun-windows-x64\bun.exe") { return $true }
                if ($Path -like "*Links") { return $true }
                if ($LiteralPath -like "*Links\bun.exe") { return $true }
                return $false
            }
            Mock Get-Item {
                return [PSCustomObject]@{ LinkType = ""; Length = 100; LastWriteTimeUtc = [datetime]'2024-01-01' }
            } -ParameterFilter { $LiteralPath -like "*Links\bun.exe" }
            Mock New-Item { throw "Bun should not create command shims" } -ParameterFilter {
                $ItemType -eq "SymbolicLink" -or $ItemType -eq "HardLink"
            }
            Mock Remove-Item { }
            Mock Copy-Item { throw "Bun should not copy command shims" }
            Mock Get-UserEnvironmentPath { return "C:\Windows" }
            Mock Set-UserEnvironmentPath { }
            Mock Write-Host { }
        }

        It 'should add the real bun directory and remove old shims without recreating them' {
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            Should -Invoke Remove-Item -Times 1 -ParameterFilter { $LiteralPath -like "*Links\bun.exe" }
            Should -Invoke Set-UserEnvironmentPath -Times 1 -ParameterFilter { $Path -like "*$script:bunBinDir*" }
            Should -Invoke New-Item -Times 0 -ParameterFilter { $ItemType -eq "SymbolicLink" -or $ItemType -eq "HardLink" }
            Should -Invoke Copy-Item -Times 0
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

        It 'should remove the stale link without recreating it' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            Should -Invoke Remove-Item -Times 1 -ParameterFilter { $LiteralPath -like "*Links\bun.exe" }
            Should -Invoke New-Item -Times 0 -ParameterFilter { $ItemType -eq "SymbolicLink" -or $ItemType -eq "HardLink" }
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

        It 'should remove the old shim and add the executable directory to PATH' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            Should -Invoke Set-UserEnvironmentPath -Times 1
            Should -Invoke Remove-Item -Times 1 -ParameterFilter { $LiteralPath -like "*Links\bun.exe" }
            Should -Invoke Copy-Item -Times 0
            Should -Invoke New-Item -Times 0 -ParameterFilter { $ItemType -eq "SymbolicLink" -or $ItemType -eq "HardLink" }
        }
    }
}
