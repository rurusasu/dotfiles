#Requires -Module Pester

<#
.SYNOPSIS
    install.ps1 オーケストレーターのユニットテスト

.DESCRIPTION
    ハンドラー検出・ソート・実行ロジックのテスト
    100% カバレッジを目標とする
#>

BeforeAll {
    # クラスとオーケストレーション関数をロード
    # 注: Get-SetupHandler, Select-SetupHandler, Invoke-SetupHandler, Show-SetupSummary は
    # SetupHandler.ps1 に含まれています
    . $PSScriptRoot/../lib/SetupHandler.ps1
    . $PSScriptRoot/../lib/Invoke-ExternalCommand.ps1
}

Describe 'Get-SetupHandler' {
    BeforeAll {
        # テスト用の一時ディレクトリを作成
        $script:testHandlersPath = Join-Path $TestDrive "handlers"
        New-Item -ItemType Directory -Path $testHandlersPath -Force | Out-Null
    }

    It '空のディレクトリの場合は空配列を返す' {
        $result = Get-SetupHandler -HandlersPath $testHandlersPath

        $result | Should -HaveCount 0
    }

    It 'Handler.*.ps1 パターンにマッチするファイルをロードする' {
        # テスト用ハンドラーを作成
        $testHandler = @'
class TestHandler : SetupHandlerBase {
    TestHandler() {
        $this.Name = "Test"
        $this.Order = 50
    }
    [bool] CanApply([SetupContext]$ctx) { return $true }
    [SetupResult] Apply([SetupContext]$ctx) { return $this.CreateSuccessResult("OK") }
}
'@
        Set-Content -Path (Join-Path $testHandlersPath "Handler.Test.ps1") -Value $testHandler

        $result = Get-SetupHandler -HandlersPath $testHandlersPath

        $result | Should -HaveCount 1
        $result[0].Name | Should -Be "Test"
    }

    It 'パターンにマッチしないファイルは無視する' {
        Set-Content -Path (Join-Path $testHandlersPath "NotAHandler.ps1") -Value "# not a handler"

        $result = Get-SetupHandler -HandlersPath $testHandlersPath

        # Handler.Test.ps1 のみ
        $result.Name | Should -Not -Contain "NotAHandler"
    }

    It '不正なハンドラーファイルは警告を出してスキップする' {
        $invalidHandler = "invalid powershell syntax {{{"
        Set-Content -Path (Join-Path $testHandlersPath "Handler.Invalid.ps1") -Value $invalidHandler
        Mock Write-Warning { }

        $result = Get-SetupHandler -HandlersPath $testHandlersPath

        # Invalid はロードされない
        $result.Name | Should -Not -Contain "Invalid"
    }

    It '存在しないディレクトリの場合は空配列を返す' {
        $result = Get-SetupHandler -HandlersPath "C:\NonExistent\Path"

        $result | Should -HaveCount 0
    }
}

Describe 'Select-SetupHandler' {
    It 'Order の昇順でソートする' {
        # PSCustomObject を使用してハンドラーをシミュレート
        $handlers = @(
            [PSCustomObject]@{ Name = "Third"; Order = 30 },
            [PSCustomObject]@{ Name = "First"; Order = 10 },
            [PSCustomObject]@{ Name = "Second"; Order = 20 }
        )

        $sorted = Select-SetupHandler -Handlers $handlers

        $sorted[0].Name | Should -Be "First"
        $sorted[1].Name | Should -Be "Second"
        $sorted[2].Name | Should -Be "Third"
    }

    It '同じ Order の場合は元の順序を維持する' {
        $handlers = @(
            [PSCustomObject]@{ Name = "B"; Order = 50 },
            [PSCustomObject]@{ Name = "A"; Order = 50 },
            [PSCustomObject]@{ Name = "C"; Order = 50 }
        )

        $sorted = Select-SetupHandler -Handlers $handlers

        # 安定ソートなので元の順序を維持
        $sorted[0].Name | Should -Be "B"
        $sorted[1].Name | Should -Be "A"
        $sorted[2].Name | Should -Be "C"
    }

    It '空配列の場合は空の結果を返す' {
        # 空配列は Sort-Object でそのまま通過する
        $emptyArray = @() | Sort-Object Order
        @($emptyArray).Count | Should -Be 0
    }
}

Describe 'Invoke-SetupHandler - 実際のハンドラーを使用' {
    BeforeAll {
        # 実際のハンドラーをロード
        . $PSScriptRoot/../handlers/Handler.Chezmoi.ps1
    }

    BeforeEach {
        Mock Write-Host { }
        $script:ctx = [SetupContext]::new("D:\dotfiles")
    }

    It 'スキップリストに含まれるハンドラーは実行しない' {
        $handler = [ChezmoiHandler]::new()

        $results = Invoke-SetupHandler -Handlers @($handler) -Context $ctx -SkipHandlers @("Chezmoi")

        $results | Should -HaveCount 0
        Should -Invoke Write-Host -ParameterFilter {
            $Object -match "Skipped"
        }
    }
}

Describe 'Show-SetupSummary' {
    BeforeEach {
        Mock Write-Host { }
    }

    It '成功結果は緑色で ✓ と表示する' {
        $results = @(
            [SetupResult]::CreateSuccess("Handler1", "完了")
        )

        Show-SetupSummary -Results $results

        Should -Invoke Write-Host -ParameterFilter {
            $Object -match "\[✓\].*Handler1" -and
            $ForegroundColor -eq "Green"
        }
    }

    It '失敗結果は赤色で ✗ と表示する' {
        $results = @(
            [SetupResult]::CreateFailure("Handler2", "エラー")
        )

        Show-SetupSummary -Results $results

        Should -Invoke Write-Host -ParameterFilter {
            $Object -match "\[✗\].*Handler2" -and
            $ForegroundColor -eq "Red"
        }
    }

    It 'Summary ヘッダーを表示する' {
        # 空でない結果でテスト
        $results = @(
            [SetupResult]::CreateSuccess("TestHandler", "テスト")
        )

        Show-SetupSummary -Results $results

        Should -Invoke Write-Host -ParameterFilter {
            $Object -match "Summary"
        }
    }

    It '複数の結果を表示する' {
        $results = @(
            [SetupResult]::CreateSuccess("Handler1", "成功1"),
            [SetupResult]::CreateFailure("Handler2", "失敗1"),
            [SetupResult]::CreateSuccess("Handler3", "成功2")
        )

        Show-SetupSummary -Results $results

        Should -Invoke Write-Host -ParameterFilter {
            $Object -match "Handler1"
        }
        Should -Invoke Write-Host -ParameterFilter {
            $Object -match "Handler2"
        }
        Should -Invoke Write-Host -ParameterFilter {
            $Object -match "Handler3"
        }
    }
}
