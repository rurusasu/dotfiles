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
    $script:projectRoot = git -C $PSScriptRoot rev-parse --show-toplevel
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

    Context 'CanApply - codex.exe link already exists' {
        BeforeEach {
            # Mock: Codex パッケージが存在
            Mock Get-ChildItem {
                return [PSCustomObject]@{
                    FullName = "C:\Users\test\AppData\Local\Microsoft\WinGet\Packages\OpenAI.Codex_Microsoft.Winget.Source_8wekyb3d8bbwe"
                }
            } -ParameterFilter {
                $Path -like "*WinGet\Packages" -and $Filter -like "OpenAI.Codex_*"
            }

            # Mock: codex-x86_64-pc-windows-msvc.exe が存在
            Mock Test-Path { return $true }
            Mock Write-Host { }
        }

        It 'should return false when link exists' {
            $result = $handler.CanApply($ctx)
            # codex.exe も存在するので false
            $result | Should -Be $false
        }
    }

    Context 'CanApply - Codex installed but no link' {
        BeforeEach {
            # Mock: Codex パッケージが存在
            Mock Get-ChildItem {
                return [PSCustomObject]@{
                    FullName = "C:\Users\test\AppData\Local\Microsoft\WinGet\Packages\OpenAI.Codex_Microsoft.Winget.Source_8wekyb3d8bbwe"
                }
            } -ParameterFilter {
                $Path -like "*WinGet\Packages" -and $Filter -like "OpenAI.Codex_*"
            }

            # Mock: codex-x86_64-pc-windows-msvc.exe は存在するが codex.exe は存在しない
            Mock Test-Path {
                param($Path)
                if ($Path -like "*codex-x86_64-pc-windows-msvc.exe") { return $true }
                if ($Path -like "*Links\codex.exe") { return $false }
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
            # Mock: Codex パッケージが存在しない → GetCodexExecutablePath が null を返す
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

    Context 'Apply - creates link successfully' {
        BeforeEach {
            # Mock: Codex パッケージが存在
            Mock Get-ChildItem {
                return [PSCustomObject]@{
                    FullName = "C:\Users\test\AppData\Local\Microsoft\WinGet\Packages\OpenAI.Codex_Microsoft.Winget.Source_8wekyb3d8bbwe"
                }
            } -ParameterFilter {
                $Path -like "*WinGet\Packages" -and $Filter -like "OpenAI.Codex_*"
            }

            # Mock: ファイルパス
            Mock Test-Path {
                param($Path)
                if ($Path -like "*codex-x86_64-pc-windows-msvc.exe") { return $true }
                if ($Path -like "*Links") { return $true }
                return $false
            }

            # Mock: リンク/コピー作成
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
            # Mock: Codex パッケージが存在
            Mock Get-ChildItem {
                return [PSCustomObject]@{
                    FullName = "C:\Users\test\AppData\Local\Microsoft\WinGet\Packages\OpenAI.Codex_Microsoft.Winget.Source_8wekyb3d8bbwe"
                }
            } -ParameterFilter {
                $Path -like "*WinGet\Packages" -and $Filter -like "OpenAI.Codex_*"
            }

            Mock Test-Path {
                param($Path)
                if ($Path -like "*codex-x86_64-pc-windows-msvc.exe") { return $true }
                if ($Path -like "*Links") { return $true }
                return $false
            }

            # Mock: シンボリックリンクとハードリンクは失敗
            Mock New-Item { throw "Administrator privilege required" } -ParameterFilter {
                $ItemType -eq "SymbolicLink" -or $ItemType -eq "HardLink"
            }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "Directory" }

            # Mock: コピーは成功
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
