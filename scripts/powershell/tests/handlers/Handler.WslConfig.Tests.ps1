#Requires -Module Pester

<#
.SYNOPSIS
    Handler.WslConfig.ps1 のユニットテスト

.DESCRIPTION
    WslConfigHandler クラスのテスト
    .wslconfig のコピーと WSL 再起動のみをテスト
    VHD 管理は Handler.VhdManager.Tests.ps1 でテスト
#>

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.WslConfig.ps1
}

Describe 'WslConfigHandler' {
    BeforeEach {
        $script:handler = [WslConfigHandler]::new()
        $script:ctx = [SetupContext]::new("D:\dotfiles")
    }

    Context 'Constructor' {
        It 'should set Name to WslConfig' {
            $handler.Name | Should -Be "WslConfig"
        }

        It 'should set Description to .wslconfig の適用' {
            $handler.Description | Should -Be ".wslconfig の適用"
        }

        It 'should set Order to 20' {
            $handler.Order | Should -Be 20
        }

        It 'should set RequiresAdmin to false' {
            $handler.RequiresAdmin | Should -Be $false
        }
    }

    Context 'CanApply' {
        It 'should return false when SkipWslConfigApply is true' {
            Mock Write-Host { }
            $ctx.Options["SkipWslConfigApply"] = $true

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }

        It 'should return false when .wslconfig does not exist' {
            Mock Test-PathExist { return $false }
            Mock Write-Host { }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }

        It 'should return true when .wslconfig exists' {
            Mock Test-PathExist { return $true }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $true
        }
    }

    Context 'Apply' {
        BeforeEach {
            Mock Test-PathExist { return $true }
            Mock Copy-FileSafe { }
            Mock Invoke-Wsl { }
            Mock Write-Host { }
        }

        It 'should copy .wslconfig and return success result' {
            $script:copyFileCalled = $false
            $script:terminateCalled = $false
            Mock Copy-FileSafe { $script:copyFileCalled = $true }
            Mock Invoke-Wsl {
                param($Arguments)
                if ($Arguments -contains "--terminate") {
                    $script:terminateCalled = $true
                }
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Be ".wslconfig を適用しました"
            $script:copyFileCalled | Should -Be $true
            $script:terminateCalled | Should -Be $true
        }

        It 'should return failure when Copy-FileSafe throws exception' {
            Mock Copy-FileSafe { throw "アクセス拒否" }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "ファイルコピーに失敗"
        }

        It 'should return failure with exception message when Invoke-Wsl throws' {
            Mock Copy-FileSafe { }
            Mock Invoke-Wsl { throw "予期しないWSLエラー" }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "予期しないWSLエラー"
        }
    }
}
