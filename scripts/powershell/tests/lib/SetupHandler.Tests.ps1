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
        It 'DotfilesPath を設定できる' {
            $ctx = [SetupContext]::new("D:\dotfiles")
            $ctx.DotfilesPath | Should -Be "D:\dotfiles"
        }

        It 'デフォルトの DistroName は NixOS' {
            $ctx = [SetupContext]::new("D:\dotfiles")
            $ctx.DistroName | Should -Be "NixOS"
        }

        It 'InstallDir が USERPROFILE\NixOS に設定される' {
            $ctx = [SetupContext]::new("D:\dotfiles")
            $ctx.InstallDir | Should -Be (Join-Path $env:USERPROFILE "NixOS")
        }

        It 'Options が空の hashtable で初期化される' {
            $ctx = [SetupContext]::new("D:\dotfiles")
            $ctx.Options | Should -BeOfType [hashtable]
            $ctx.Options.Count | Should -Be 0
        }
    }

    Context 'GetOption' {
        It 'キーが存在する場合は値を返す' {
            $ctx = [SetupContext]::new("D:\dotfiles")
            $ctx.Options["TestKey"] = "TestValue"
            $ctx.GetOption("TestKey", "Default") | Should -Be "TestValue"
        }

        It 'キーが存在しない場合はデフォルト値を返す' {
            $ctx = [SetupContext]::new("D:\dotfiles")
            $ctx.GetOption("NonExistentKey", "DefaultValue") | Should -Be "DefaultValue"
        }

        It 'デフォルト値が $null の場合' {
            $ctx = [SetupContext]::new("D:\dotfiles")
            $ctx.GetOption("NonExistentKey", $null) | Should -BeNullOrEmpty
        }

        It 'デフォルト値が $false の場合' {
            $ctx = [SetupContext]::new("D:\dotfiles")
            $ctx.GetOption("NonExistentKey", $false) | Should -Be $false
        }

        It 'デフォルト値が数値の場合' {
            $ctx = [SetupContext]::new("D:\dotfiles")
            $ctx.GetOption("NonExistentKey", 42) | Should -Be 42
        }
    }

    Context 'プロパティ設定' {
        It 'DistroName を変更できる' {
            $ctx = [SetupContext]::new("D:\dotfiles")
            $ctx.DistroName = "Ubuntu"
            $ctx.DistroName | Should -Be "Ubuntu"
        }

        It 'InstallDir を変更できる' {
            $ctx = [SetupContext]::new("D:\dotfiles")
            $ctx.InstallDir = "C:\WSL\NixOS"
            $ctx.InstallDir | Should -Be "C:\WSL\NixOS"
        }

        It 'Options に複数のキーを設定できる' {
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
        It 'デフォルトで Success は $false' {
            $result = [SetupResult]::new()
            $result.Success | Should -Be $false
        }

        It 'デフォルトで Message は空文字' {
            $result = [SetupResult]::new()
            $result.Message | Should -Be ""
        }

        It 'デフォルトで Error は $null' {
            $result = [SetupResult]::new()
            $result.Error | Should -BeNullOrEmpty
        }
    }

    Context 'CreateSuccess' {
        It '成功結果を作成できる' {
            $result = [SetupResult]::CreateSuccess("TestHandler", "処理が完了しました")
            
            $result.HandlerName | Should -Be "TestHandler"
            $result.Success | Should -Be $true
            $result.Message | Should -Be "処理が完了しました"
            $result.Error | Should -BeNullOrEmpty
        }

        It '空のメッセージでも作成できる' {
            $result = [SetupResult]::CreateSuccess("TestHandler", "")
            
            $result.Success | Should -Be $true
            $result.Message | Should -Be ""
        }
    }

    Context 'CreateFailure' {
        It '失敗結果を作成できる（例外なし）' {
            $result = [SetupResult]::CreateFailure("TestHandler", "エラーが発生しました")
            
            $result.HandlerName | Should -Be "TestHandler"
            $result.Success | Should -Be $false
            $result.Message | Should -Be "エラーが発生しました"
            $result.Error | Should -BeNullOrEmpty
        }

        It '失敗結果を作成できる（例外あり）' {
            $exception = [System.Exception]::new("Test exception")
            $result = [SetupResult]::CreateFailure("TestHandler", "エラーが発生しました", $exception)
            
            $result.HandlerName | Should -Be "TestHandler"
            $result.Success | Should -Be $false
            $result.Message | Should -Be "エラーが発生しました"
            $result.Error | Should -Be $exception
            $result.Error.Message | Should -Be "Test exception"
        }

        It '例外が $null でも作成できる' {
            $result = [SetupResult]::CreateFailure("TestHandler", "エラー", $null)
            
            $result.Success | Should -Be $false
            $result.Error | Should -BeNullOrEmpty
        }
    }
}

Describe 'SetupHandlerBase' {
    Context 'プロパティ' {
        It 'デフォルトの Order は 100' {
            $handler = [SetupHandlerBase]::new()
            $handler.Order | Should -Be 100
        }

        It 'デフォルトの RequiresAdmin は $false' {
            $handler = [SetupHandlerBase]::new()
            $handler.RequiresAdmin | Should -Be $false
        }

        It 'Order を設定できる' {
            $handler = [SetupHandlerBase]::new()
            $handler.Order = 50
            $handler.Order | Should -Be 50
        }

        It 'Name を設定できる' {
            $handler = [SetupHandlerBase]::new()
            $handler.Name = "TestHandler"
            $handler.Name | Should -Be "TestHandler"
        }

        It 'Description を設定できる' {
            $handler = [SetupHandlerBase]::new()
            $handler.Description = "テスト用ハンドラー"
            $handler.Description | Should -Be "テスト用ハンドラー"
        }
    }

    Context 'CanApply (基底クラス)' {
        It '基底クラスの CanApply は例外をスロー' {
            $handler = [SetupHandlerBase]::new()
            $ctx = [SetupContext]::new("D:\dotfiles")
            
            { $handler.CanApply($ctx) } | Should -Throw "*must be implemented*"
        }
    }

    Context 'Apply (基底クラス)' {
        It '基底クラスの Apply は例外をスロー' {
            $handler = [SetupHandlerBase]::new()
            $ctx = [SetupContext]::new("D:\dotfiles")
            
            { $handler.Apply($ctx) } | Should -Throw "*must be implemented*"
        }
    }

    Context 'CreateSuccessResult' {
        It '成功結果を作成できる' {
            $handler = [SetupHandlerBase]::new()
            $handler.Name = "TestHandler"
            $result = $handler.CreateSuccessResult("テスト成功")
            
            $result.HandlerName | Should -Be "TestHandler"
            $result.Success | Should -Be $true
            $result.Message | Should -Be "テスト成功"
        }
    }

    Context 'CreateFailureResult' {
        It '失敗結果を作成できる（例外なし）' {
            $handler = [SetupHandlerBase]::new()
            $handler.Name = "TestHandler"
            $result = $handler.CreateFailureResult("テスト失敗")
            
            $result.HandlerName | Should -Be "TestHandler"
            $result.Success | Should -Be $false
            $result.Message | Should -Be "テスト失敗"
            $result.Error | Should -BeNullOrEmpty
        }

        It '失敗結果を作成できる（例外あり）' {
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
        It 'Log はメッセージを出力する' {
            $handler = [SetupHandlerBase]::new()
            $handler.Name = "TestHandler"
            
            Mock Write-Host { }
            
            $handler.Log("テストメッセージ")
            
            Should -Invoke Write-Host -Times 1 -ParameterFilter {
                $Object -eq "[TestHandler] テストメッセージ" -and
                $ForegroundColor -eq "Cyan"
            }
        }

        It 'Log は色を指定できる' {
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

    Context 'LogWarning メソッド' {
        It 'LogWarning は黄色でメッセージを出力する' {
            $handler = [SetupHandlerBase]::new()
            $handler.Name = "TestHandler"
            
            Mock Write-Host { }
            
            $handler.LogWarning("警告メッセージ")
            
            Should -Invoke Write-Host -Times 1 -ParameterFilter {
                $Object -eq "[TestHandler] 警告メッセージ" -and
                $ForegroundColor -eq "Yellow"
            }
        }
    }

    Context 'LogError メソッド' {
        It 'LogError は赤色でメッセージを出力する' {
            $handler = [SetupHandlerBase]::new()
            $handler.Name = "TestHandler"
            
            Mock Write-Host { }
            
            $handler.LogError("エラーメッセージ")
            
            Should -Invoke Write-Host -Times 1 -ParameterFilter {
                $Object -eq "[TestHandler] エラーメッセージ" -and
                $ForegroundColor -eq "Red"
            }
        }
    }
}
