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

    Context 'NeedsConsent' {
        It 'should return false when ConsentKey is empty' {
            $handler = [SetupHandlerBase]::new()
            $handler.NeedsConsent() | Should -Be $false
        }

        It 'should return true when ConsentKey is set' {
            $handler = [SetupHandlerBase]::new()
            $handler.ConsentKey = "test_enabled"
            $handler.NeedsConsent() | Should -Be $true
        }
    }

    Context 'GetConsentFilePath' {
        It 'should return path under .config/dotfiles' {
            $handler = [SetupHandlerBase]::new()
            $path = $handler.GetConsentFilePath()
            $path | Should -BeLike "*\.config\dotfiles\consent.json"
        }
    }

    Context 'ReadConsentFlag' {
        BeforeEach {
            $script:handler = [SetupHandlerBase]::new()
            $script:handler.ConsentKey = "test_enabled"
            $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "consent-test-$([guid]::NewGuid().ToString('N').Substring(0,8))"
            New-Item -ItemType Directory -Path $script:tempDir -Force | Out-Null
            $script:tempFile = Join-Path $script:tempDir "consent.json"
            # GetConsentFilePath をオーバーライドするため、テスト用パスを返すようモック
            $script:handler | Add-Member -MemberType ScriptMethod -Name GetConsentFilePath -Value {
                return $script:tempFile
            } -Force
        }

        AfterEach {
            if (Test-Path $script:tempDir) {
                Remove-Item -Path $script:tempDir -Recurse -Force
            }
        }

        It 'should return null when ConsentKey is empty' {
            $handler2 = [SetupHandlerBase]::new()
            $handler2.ReadConsentFlag() | Should -BeNullOrEmpty
        }

        It 'should return null when consent.json does not exist' {
            $script:handler.ReadConsentFlag() | Should -BeNullOrEmpty
        }

        It 'should return true when key is true' {
            @{ test_enabled = $true } | ConvertTo-Json | Set-Content -Path $script:tempFile -Encoding UTF8
            $script:handler.ReadConsentFlag() | Should -Be $true
        }

        It 'should return false when key is false' {
            @{ test_enabled = $false } | ConvertTo-Json | Set-Content -Path $script:tempFile -Encoding UTF8
            $script:handler.ReadConsentFlag() | Should -Be $false
        }

        It 'should return null when key does not exist in JSON' {
            @{ other_key = $true } | ConvertTo-Json | Set-Content -Path $script:tempFile -Encoding UTF8
            $script:handler.ReadConsentFlag() | Should -BeNullOrEmpty
        }

        It 'should return null when JSON is corrupt' {
            "not valid json {{{" | Set-Content -Path $script:tempFile -Encoding UTF8
            $script:handler.ReadConsentFlag() | Should -BeNullOrEmpty
        }
    }

    Context 'WriteConsentFlag' {
        BeforeEach {
            $script:handler = [SetupHandlerBase]::new()
            $script:handler.ConsentKey = "test_enabled"
            $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "consent-test-$([guid]::NewGuid().ToString('N').Substring(0,8))"
            New-Item -ItemType Directory -Path $script:tempDir -Force | Out-Null
            $script:tempFile = Join-Path $script:tempDir "consent.json"
            $script:handler | Add-Member -MemberType ScriptMethod -Name GetConsentFilePath -Value {
                return $script:tempFile
            } -Force
        }

        AfterEach {
            if (Test-Path $script:tempDir) {
                Remove-Item -Path $script:tempDir -Recurse -Force
            }
        }

        It 'should create consent.json with true value' {
            $script:handler.WriteConsentFlag($true)
            $json = Get-Content $script:tempFile -Raw | ConvertFrom-Json
            $json.test_enabled | Should -Be $true
        }

        It 'should create consent.json with false value' {
            $script:handler.WriteConsentFlag($false)
            $json = Get-Content $script:tempFile -Raw | ConvertFrom-Json
            $json.test_enabled | Should -Be $false
        }

        It 'should preserve existing keys when writing' {
            @{ other_key = $true } | ConvertTo-Json | Set-Content -Path $script:tempFile -Encoding UTF8
            $script:handler.WriteConsentFlag($true)
            $json = Get-Content $script:tempFile -Raw | ConvertFrom-Json
            $json.test_enabled | Should -Be $true
            $json.other_key | Should -Be $true
        }

        It 'should update existing key value' {
            @{ test_enabled = $true } | ConvertTo-Json | Set-Content -Path $script:tempFile -Encoding UTF8
            $script:handler.WriteConsentFlag($false)
            $json = Get-Content $script:tempFile -Raw | ConvertFrom-Json
            $json.test_enabled | Should -Be $false
        }

        It 'should create directory if it does not exist' {
            $nestedDir = Join-Path $script:tempDir "nested\dir"
            $nestedFile = Join-Path $nestedDir "consent.json"
            $script:handler | Add-Member -MemberType ScriptMethod -Name GetConsentFilePath -Value {
                return $nestedFile
            } -Force

            $script:handler.WriteConsentFlag($true)
            Test-Path $nestedFile | Should -Be $true
            $json = Get-Content $nestedFile -Raw | ConvertFrom-Json
            $json.test_enabled | Should -Be $true
        }

        It 'should handle corrupt JSON gracefully and overwrite' {
            "broken json {{" | Set-Content -Path $script:tempFile -Encoding UTF8
            $script:handler.WriteConsentFlag($true)
            $json = Get-Content $script:tempFile -Raw | ConvertFrom-Json
            $json.test_enabled | Should -Be $true
        }

        It 'should do nothing when ConsentKey is empty' {
            $handler2 = [SetupHandlerBase]::new()
            $handler2 | Add-Member -MemberType ScriptMethod -Name GetConsentFilePath -Value {
                return $script:tempFile
            } -Force
            $handler2.WriteConsentFlag($true)
            Test-Path $script:tempFile | Should -Be $false
        }
    }

    Context 'Log メソッド' {
        BeforeEach {
            Mock Write-Host { }
        }

        It 'should output message with Cyan color' {
            $handler = [SetupHandlerBase]::new()
            $handler.Name = "TestHandler"

            $handler.Log("テストメッセージ")

            Should -Invoke Write-Host -Times 1 -ParameterFilter {
                $Object -eq "[TestHandler] テストメッセージ" -and
                $ForegroundColor -eq "Cyan"
            }
        }

        It 'should output message with Yellow color' {
            $handler = [SetupHandlerBase]::new()
            $handler.Name = "TestHandler"

            $handler.LogWarning("警告メッセージ")

            Should -Invoke Write-Host -Times 1 -ParameterFilter {
                $Object -eq "[TestHandler] 警告メッセージ" -and
                $ForegroundColor -eq "Yellow"
            }
        }

        It 'should output message with Red color' {
            $handler = [SetupHandlerBase]::new()
            $handler.Name = "TestHandler"

            $handler.LogError("エラーメッセージ")

            Should -Invoke Write-Host -Times 1 -ParameterFilter {
                $Object -eq "[TestHandler] エラーメッセージ" -and
                $ForegroundColor -eq "Red"
            }
        }

        It 'should allow custom color for Log method' {
            $handler = [SetupHandlerBase]::new()
            $handler.Name = "TestHandler"

            $handler.Log("テストメッセージ", "Green")

            Should -Invoke Write-Host -Times 1 -ParameterFilter {
                $Object -eq "[TestHandler] テストメッセージ" -and
                $ForegroundColor -eq "Green"
            }
        }
    }
}
