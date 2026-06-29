#Requires -Module Pester

<#
.SYNOPSIS
    Handler.Codex.ps1 のユニットテスト

.DESCRIPTION
    CodexHandler クラスのテスト
#>

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.Codex.ps1
    $script:projectRoot = (Resolve-Path -LiteralPath "$PSScriptRoot/../../../..").Path

    # GetCodexExecutablePath() が返すパス（パッケージ dir + 実行ファイル名）
    $script:codexPkgDir = "C:\Users\test\AppData\Local\Microsoft\WinGet\Packages\OpenAI.Codex_Microsoft.Winget.Source_8wekyb3d8bbwe"
    $script:codexExe = Join-Path $script:codexPkgDir "codex-x86_64-pc-windows-msvc.exe"
    $script:homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { [Environment]::GetFolderPath("UserProfile") }
    $script:localAppData = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $script:homeDir "AppData\Local" }
    $script:expectedLinks = Join-Path $script:localAppData "Microsoft\WinGet\Links"
    $script:expectedLocalBin = Join-Path $script:homeDir ".local\bin"

    # Codex パッケージが存在することにする共通モック
    function script:Set-CodexPackageInstalled {
        Mock Get-ChildItem {
            return [PSCustomObject]@{ FullName = $script:codexPkgDir }
        } -ParameterFilter {
            $Path -like "*WinGet\Packages" -and $Filter -like "OpenAI.Codex_*"
        }
    }
}

Describe 'CodexHandler' {
    BeforeEach {
        $script:handler = [CodexHandler]::new()
        $script:ctx = [SetupContext]::new($script:projectRoot)
    }

    Context 'Constructor' {
        It 'should set <property> correctly' -ForEach @(
            @{ property = "Name"; expected = "Codex"; checkType = "Be" }
            @{ property = "Description"; expected = $null; checkType = "Not -BeNullOrEmpty" }
            @{ property = "Order"; expected = 6; checkType = "Be" }
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

    Context 'CanApply - Codex not installed' {
        BeforeEach {
            Mock Get-ChildItem { return $null } -ParameterFilter {
                $Path -like "*WinGet\Packages" -and $Filter -like "OpenAI.Codex_*"
            }
            Mock Write-Host { }
        }

        It 'should return false' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $false
        }
    }

    Context 'CanApply - link is current AND PATH configured' {
        BeforeEach {
            Set-CodexPackageInstalled
            Mock Test-Path {
                if ($Path -like "*codex-x86_64-pc-windows-msvc.exe") { return $true }
                if ($LiteralPath -like "*Links\codex.exe") { return $true }
                return $false
            }
            # 現行 exe を指すシンボリックリンク
            Mock Get-Item {
                return [PSCustomObject]@{ LinkType = "SymbolicLink"; Target = $script:codexExe }
            } -ParameterFilter { $LiteralPath -like "*Links\codex.exe" }
            Mock Get-UserEnvironmentPath { return "C:\Windows;$script:expectedLinks;$script:expectedLocalBin" }
            Mock Write-Host { }
        }

        It 'should return false when link and PATH are both set' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $false
        }
    }

    Context 'CanApply - link is stale copy from old version (winget upgrade)' {
        BeforeEach {
            Set-CodexPackageInstalled
            Mock Test-Path {
                if ($Path -like "*codex-x86_64-pc-windows-msvc.exe") { return $true }
                if ($LiteralPath -like "*Links\codex.exe") { return $true }
                return $false
            }
            # Links\codex.exe は旧バージョンのコピー（symlink ではない）。
            # 現行 exe とサイズ/更新日時が異なる。
            Mock Get-Item {
                if ($LiteralPath -like "*Links\codex.exe") {
                    return [PSCustomObject]@{ LinkType = ""; Length = 174106600; LastWriteTimeUtc = [datetime]'2024-01-01' }
                }
                return [PSCustomObject]@{ LinkType = ""; Length = 246156592; LastWriteTimeUtc = [datetime]'2024-06-01' }
            }
            Mock Get-UserEnvironmentPath { return "C:\Windows;$script:expectedLinks" }
            Mock Write-Host { }
        }

        It 'should return true so the stale link is refreshed' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $true
        }
    }

    Context 'CanApply - link is matching copy instead of symlink' {
        BeforeEach {
            Set-CodexPackageInstalled
            Mock Test-Path {
                if ($Path -like "*codex-x86_64-pc-windows-msvc.exe") { return $true }
                if ($LiteralPath -like "*Links\codex.exe") { return $true }
                return $false
            }
            # 現行 exe と一致するコピーでも、winget upgrade 後に陳腐化する。
            Mock Get-Item {
                return [PSCustomObject]@{ LinkType = ""; Length = 246156592; LastWriteTimeUtc = [datetime]'2024-06-01' }
            }
            Mock Get-UserEnvironmentPath { return "C:\Windows;$script:expectedLinks;$script:expectedLocalBin" }
            Mock Write-Host { }
        }

        It 'should return true so the copy is replaced with a symlink' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $true
        }
    }

    Context 'CanApply - link is current but PATH not configured' {
        BeforeEach {
            Set-CodexPackageInstalled
            Mock Test-Path {
                if ($Path -like "*codex-x86_64-pc-windows-msvc.exe") { return $true }
                if ($LiteralPath -like "*Links\codex.exe") { return $true }
                return $false
            }
            Mock Get-Item {
                return [PSCustomObject]@{ LinkType = "SymbolicLink"; Target = $script:codexExe }
            } -ParameterFilter { $LiteralPath -like "*Links\codex.exe" }
            Mock Get-UserEnvironmentPath { return "C:\Windows;C:\Windows\System32" }
            Mock Write-Host { }
        }

        It 'should return true so Apply can add PATH' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $true
        }
    }

    Context 'CanApply - link and WinGet PATH configured but local bin missing' {
        BeforeEach {
            Set-CodexPackageInstalled
            Mock Test-Path {
                if ($Path -like "*codex-x86_64-pc-windows-msvc.exe") { return $true }
                if ($LiteralPath -like "*Links\codex.exe") { return $true }
                return $false
            }
            Mock Get-Item {
                return [PSCustomObject]@{ LinkType = "SymbolicLink"; Target = $script:codexExe }
            } -ParameterFilter { $LiteralPath -like "*Links\codex.exe" }
            Mock Get-UserEnvironmentPath { return "C:\Windows;$script:expectedLinks" }
            Mock Write-Host { }
        }

        It 'should return true so Apply can add local bin for MCP tools' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $true
        }
    }

    Context 'CanApply - Codex installed but no link' {
        BeforeEach {
            Set-CodexPackageInstalled
            Mock Test-Path {
                if ($Path -like "*codex-x86_64-pc-windows-msvc.exe") { return $true }
                if ($LiteralPath -like "*Links\codex.exe") { return $false }
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
                $Path -like "*WinGet\Packages" -and $Filter -like "OpenAI.Codex_*"
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
            Set-CodexPackageInstalled
            Mock Test-Path {
                if ($Path -like "*codex-x86_64-pc-windows-msvc.exe") { return $true }
                if ($Path -like "*Links") { return $true }
                if ($LiteralPath -like "*Links\codex.exe") { return $false }
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

    Context 'Apply - fails when symlink cannot be created' {
        BeforeEach {
            Set-CodexPackageInstalled
            Mock Test-Path {
                if ($Path -like "*codex-x86_64-pc-windows-msvc.exe") { return $true }
                if ($Path -like "*Links") { return $true }
                if ($LiteralPath -like "*Links\codex.exe") { return $false }
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

        It 'should not fallback to hardlink or copy' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $false
            $result.Message | Should -Match "シンボリックリンク"
            Should -Invoke New-Item -Times 1 -ParameterFilter { $ItemType -eq "SymbolicLink" }
            Should -Invoke New-Item -Times 0 -ParameterFilter { $ItemType -eq "HardLink" }
            Should -Invoke Copy-Item -Times 0
        }
    }

    Context 'Apply - refreshes stale link after winget upgrade' {
        BeforeEach {
            Set-CodexPackageInstalled
            Mock Test-Path {
                if ($Path -like "*codex-x86_64-pc-windows-msvc.exe") { return $true }
                if ($Path -like "*Links") { return $true }
                if ($LiteralPath -like "*Links\codex.exe") { return $true }
                return $false
            }
            # 既存リンクは旧バージョンのコピーで陳腐化している
            Mock Get-Item {
                if ($LiteralPath -like "*Links\codex.exe") {
                    return [PSCustomObject]@{ LinkType = ""; Length = 174106600; LastWriteTimeUtc = [datetime]'2024-01-01' }
                }
                return [PSCustomObject]@{ LinkType = ""; Length = 246156592; LastWriteTimeUtc = [datetime]'2024-06-01' }
            }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "SymbolicLink" }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "Directory" }
            Mock Remove-Item { }
            Mock Copy-Item { }
            Mock Get-UserEnvironmentPath { return "C:\Windows;$script:expectedLinks" }
            Mock Set-UserEnvironmentPath { }
            Mock Write-Host { }
        }

        It 'should remove the stale link and recreate it' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            Should -Invoke Remove-Item -Times 1 -ParameterFilter { $LiteralPath -like "*Links\codex.exe" }
            Should -Invoke New-Item -Times 1 -ParameterFilter { $ItemType -eq "SymbolicLink" }
        }
    }

    Context 'Apply - link current, only PATH missing' {
        BeforeEach {
            Set-CodexPackageInstalled
            Mock Test-Path {
                if ($Path -like "*codex-x86_64-pc-windows-msvc.exe") { return $true }
                if ($Path -like "*Links") { return $true }
                if ($LiteralPath -like "*Links\codex.exe") { return $true }
                return $false
            }
            # 既存リンクは現行 exe を指すシンボリックリンク（最新）
            Mock Get-Item {
                return [PSCustomObject]@{ LinkType = "SymbolicLink"; Target = $script:codexExe }
            } -ParameterFilter { $LiteralPath -like "*Links\codex.exe" }
            Mock New-Item { throw "should not recreate a current link" } -ParameterFilter {
                $ItemType -eq "SymbolicLink" -or $ItemType -eq "HardLink"
            }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "Directory" }
            Mock Remove-Item { }
            Mock Copy-Item { }
            Mock Get-UserEnvironmentPath { return "C:\Windows;C:\Windows\System32;$script:expectedLocalBin" }
            Mock Set-UserEnvironmentPath { }
            Mock Write-Host { }
        }

        It 'should add WinGet Links PATH without recreating the link' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            Should -Invoke Set-UserEnvironmentPath -Times 1
            Should -Invoke Copy-Item -Times 0
            Should -Invoke New-Item -Times 0 -ParameterFilter { $ItemType -eq "SymbolicLink" -or $ItemType -eq "HardLink" }
        }
    }

    Context 'Apply - link current, only local bin missing' {
        BeforeEach {
            Set-CodexPackageInstalled
            Mock Test-Path {
                if ($Path -like "*codex-x86_64-pc-windows-msvc.exe") { return $true }
                if ($Path -like "*Links") { return $true }
                if ($LiteralPath -like "*Links\codex.exe") { return $true }
                return $false
            }
            Mock Get-Item {
                return [PSCustomObject]@{ LinkType = "SymbolicLink"; Target = $script:codexExe }
            } -ParameterFilter { $LiteralPath -like "*Links\codex.exe" }
            Mock New-Item { throw "should not recreate a current link" } -ParameterFilter {
                $ItemType -eq "SymbolicLink" -or $ItemType -eq "HardLink"
            }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "Directory" }
            Mock Remove-Item { }
            Mock Copy-Item { }
            Mock Get-UserEnvironmentPath { return "C:\Windows;$script:expectedLinks" }
            Mock Set-UserEnvironmentPath { }
            Mock Write-Host { }
        }

        It 'should add local bin for MCP tools without recreating the link' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            Should -Invoke Set-UserEnvironmentPath -Times 1 -ParameterFilter { $Path -like "$script:expectedLocalBin*" }
            Should -Invoke Copy-Item -Times 0
            Should -Invoke New-Item -Times 0 -ParameterFilter { $ItemType -eq "SymbolicLink" -or $ItemType -eq "HardLink" }
        }
    }
}
