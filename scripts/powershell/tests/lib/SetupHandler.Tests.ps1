#Requires -Module Pester

<#
.SYNOPSIS
    SetupHandler.ps1 のユニットテスト

.DESCRIPTION
    SetupContext, SetupResult, SetupHandlerBase クラスのテスト
    100% カバレッジを目標とする
#>

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
}

Describe 'SetupContext' {
    Context 'コンストラクタ' {
        It 'should set DotfilesPath correctly' {
            $ctx = [SetupContext]::new("D:\dotfiles")
            $ctx.DotfilesPath | Should -Be "D:\dotfiles"
        }

        It 'should default DistroName to NixOS' {
            $ctx = [SetupContext]::new("D:\dotfiles")
            $ctx.DistroName | Should -Be "NixOS"
        }

        It 'should set InstallDir to USERPROFILE\NixOS' {
            $ctx = [SetupContext]::new("D:\dotfiles")
            $ctx.InstallDir | Should -Be (Join-Path $env:USERPROFILE "NixOS")
        }

        It 'should initialize Options as empty hashtable' {
            $ctx = [SetupContext]::new("D:\dotfiles")
            $ctx.Options | Should -BeOfType [hashtable]
            $ctx.Options.Count | Should -Be 0
        }
    }

    Context 'GetOption' {
        It 'should return <expected> when key <keyExists>' -ForEach @(
            @{ keyExists = "exists"; key = "TestKey"; setValue = "TestValue"; default = "Default"; expected = "TestValue" }
            @{ keyExists = "does not exist"; key = "NonExistentKey"; setValue = $null; default = "DefaultValue"; expected = "DefaultValue" }
        ) {
            $ctx = [SetupContext]::new("D:\dotfiles")
            if ($setValue) {
                $ctx.Options[$key] = $setValue
            }
            $ctx.GetOption($key, $default) | Should -Be $expected
        }

        It 'should return <expected> for default value type <type>' -ForEach @(
            @{ type = "null"; default = $null; expected = $null }
            @{ type = "false"; default = $false; expected = $false }
            @{ type = "number"; default = 42; expected = 42 }
        ) {
            $ctx = [SetupContext]::new("D:\dotfiles")
            $result = $ctx.GetOption("NonExistentKey", $default)
            if ($null -eq $expected) {
                $result | Should -BeNullOrEmpty
            } else {
                $result | Should -Be $expected
            }
        }
    }

    Context 'プロパティ設定' {
        It 'should allow setting <property> to <value>' -ForEach @(
            @{ property = "DistroName"; value = "Ubuntu" }
            @{ property = "InstallDir"; value = "C:\WSL\NixOS" }
        ) {
            $ctx = [SetupContext]::new("D:\dotfiles")
            $ctx.$property = $value
            $ctx.$property | Should -Be $value
        }

        It 'should allow setting multiple keys in Options' {
            $ctx = [SetupContext]::new("D:\dotfiles")
            $ctx.Options["Key1"] = "Value1"
            $ctx.Options["Key2"] = $true
            $ctx.Options["Key3"] = 123

            $ctx.GetOption("Key1", $null) | Should -Be "Value1"
            $ctx.GetOption("Key2", $false) | Should -Be $true
            $ctx.GetOption("Key3", 0) | Should -Be 123
        }
    }
}

Describe 'SetupResult' {
    Context 'コンストラクタ' {
        It 'should default <property> to <expected>' -ForEach @(
            @{ property = "Success"; expected = $false }
            @{ property = "Message"; expected = "" }
        ) {
            $result = [SetupResult]::new()
            $result.$property | Should -Be $expected
        }

        It 'should default Error to null' {
            $result = [SetupResult]::new()
            $result.Error | Should -BeNullOrEmpty
        }
    }

    Context 'CreateSuccess' {
        It 'should create success result with correct properties' {
            $result = [SetupResult]::CreateSuccess("TestHandler", "処理が完了しました")

            $result.HandlerName | Should -Be "TestHandler"
            $result.Success | Should -Be $true
            $result.Message | Should -Be "処理が完了しました"
            $result.Error | Should -BeNullOrEmpty
        }

        It 'should allow empty message' {
            $result = [SetupResult]::CreateSuccess("TestHandler", "")

            $result.Success | Should -Be $true
            $result.Message | Should -Be ""
        }
    }

    Context 'CreateFailure' {
        It 'should create failure result without exception' {
            $result = [SetupResult]::CreateFailure("TestHandler", "エラーが発生しました")

            $result.HandlerName | Should -Be "TestHandler"
            $result.Success | Should -Be $false
            $result.Message | Should -Be "エラーが発生しました"
            $result.Error | Should -BeNullOrEmpty
        }

        It 'should create failure result with exception' {
            $exception = [System.Exception]::new("Test exception")
            $result = [SetupResult]::CreateFailure("TestHandler", "エラーが発生しました", $exception)

            $result.HandlerName | Should -Be "TestHandler"
            $result.Success | Should -Be $false
            $result.Message | Should -Be "エラーが発生しました"
            $result.Error | Should -Be $exception
            $result.Error.Message | Should -Be "Test exception"
        }

        It 'should allow null exception' {
            $result = [SetupResult]::CreateFailure("TestHandler", "エラー", $null)

            $result.Success | Should -Be $false
            $result.Error | Should -BeNullOrEmpty
        }
    }
}

Describe 'SetupHandlerBase' {
    Context 'プロパティ' {
        It 'should default <property> to <expected>' -ForEach @(
            @{ property = "Order"; expected = 100 }
            @{ property = "RequiresAdmin"; expected = $false }
        ) {
            $handler = [SetupHandlerBase]::new()
            $handler.$property | Should -Be $expected
        }

        It 'should allow setting <property>' -ForEach @(
            @{ property = "Order"; value = 50 }
            @{ property = "Name"; value = "TestHandler" }
            @{ property = "Description"; value = "テスト用ハンドラー" }
        ) {
            $handler = [SetupHandlerBase]::new()
            $handler.$property = $value
            $handler.$property | Should -Be $value
        }
    }

    Context 'CanApply (基底クラス)' {
        It 'should throw exception for base class CanApply' {
            $handler = [SetupHandlerBase]::new()
            $ctx = [SetupContext]::new("D:\dotfiles")

            { $handler.CanApply($ctx) } | Should -Throw "*must be implemented*"
        }
    }

    Context 'Apply (基底クラス)' {
        It 'should throw exception for base class Apply' {
            $handler = [SetupHandlerBase]::new()
            $ctx = [SetupContext]::new("D:\dotfiles")

            { $handler.Apply($ctx) } | Should -Throw "*must be implemented*"
        }
    }

    Context 'CreateSuccessResult' {
        It 'should create success result with handler name' {
            $handler = [SetupHandlerBase]::new()
            $handler.Name = "TestHandler"
            $result = $handler.CreateSuccessResult("テスト成功")

            $result.HandlerName | Should -Be "TestHandler"
            $result.Success | Should -Be $true
            $result.Message | Should -Be "テスト成功"
        }
    }

    Context 'CreateFailureResult' {
        It 'should create failure result without exception' {
            $handler = [SetupHandlerBase]::new()
            $handler.Name = "TestHandler"
            $result = $handler.CreateFailureResult("テスト失敗")

            $result.HandlerName | Should -Be "TestHandler"
            $result.Success | Should -Be $false
            $result.Message | Should -Be "テスト失敗"
            $result.Error | Should -BeNullOrEmpty
        }

        It 'should create failure result with exception' {
            $handler = [SetupHandlerBase]::new()
            $handler.Name = "TestHandler"
            $exception = [System.IO.IOException]::new("ファイルが見つかりません")
            $result = $handler.CreateFailureResult("テスト失敗", $exception)

            $result.HandlerName | Should -Be "TestHandler"
            $result.Success | Should -Be $false
            $result.Message | Should -Be "テスト失敗"
            $result.Error | Should -Be $exception
        }
    }

    Context 'Log メソッド' {
        It 'should output message with <color> color' -ForEach @(
            @{ method = "Log"; color = "Cyan"; message = "テストメッセージ" }
            @{ method = "LogWarning"; color = "Yellow"; message = "警告メッセージ" }
            @{ method = "LogError"; color = "Red"; message = "エラーメッセージ" }
        ) {
            $handler = [SetupHandlerBase]::new()
            $handler.Name = "TestHandler"

            Mock Write-Host { }

            if ($method -eq "Log") {
                $handler.Log($message)
            } elseif ($method -eq "LogWarning") {
                $handler.LogWarning($message)
            } else {
                $handler.LogError($message)
            }

            Should -Invoke Write-Host -Times 1 -ParameterFilter {
                $Object -eq "[TestHandler] $message" -and
                $ForegroundColor -eq $color
            }
        }

        It 'should allow custom color for Log method' {
            $handler = [SetupHandlerBase]::new()
            $handler.Name = "TestHandler"

            Mock Write-Host { }

            $handler.Log("テストメッセージ", "Green")

            Should -Invoke Write-Host -Times 1 -ParameterFilter {
                $Object -eq "[TestHandler] テストメッセージ" -and
                $ForegroundColor -eq "Green"
            }
        }
    }
}
