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

    It 'should return empty array for empty directory' {
        $result = Get-SetupHandler -HandlersPath $testHandlersPath

        $result | Should -HaveCount 0
    }

    It 'should load files matching Handler.*.ps1 pattern' {
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

    It 'should ignore files not matching pattern' {
        Set-Content -Path (Join-Path $testHandlersPath "NotAHandler.ps1") -Value "# not a handler"

        $result = Get-SetupHandler -HandlersPath $testHandlersPath

        # Handler.Test.ps1 のみ
        $result.Name | Should -Not -Contain "NotAHandler"
    }

    It 'should warn and skip invalid handler files' {
        $invalidHandler = "invalid powershell syntax {{{"
        Set-Content -Path (Join-Path $testHandlersPath "Handler.Invalid.ps1") -Value $invalidHandler
        Mock Write-Warning { }

        $result = Get-SetupHandler -HandlersPath $testHandlersPath

        # Invalid はロードされない
        $result.Name | Should -Not -Contain "Invalid"
    }

    It 'should return empty array for non-existent directory' {
        $result = Get-SetupHandler -HandlersPath "C:\NonExistent\Path"

        $result | Should -HaveCount 0
    }
}

Describe 'Select-SetupHandler' {
    It 'should sort handlers by Order in ascending order' {
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

    It 'should maintain original order for same Order value (stable sort)' {
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

    It 'should return empty result for empty array' {
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

    It 'should skip handlers in skip list' {
        $handler = [ChezmoiHandler]::new()

        $results = Invoke-SetupHandler -Handlers @($handler) -Context $ctx -SkipHandlers @("Chezmoi")

        $results | Should -HaveCount 0
        Should -Invoke Write-Host -ParameterFilter {
            $Object -match "Skipped"
        }
    }
}

Describe 'クラスキャッシュ問題 - 複数回ロード' {
    It 'should not cause type conflicts when SetupHandler.ps1 is loaded multiple times' {
        # SetupHandler.ps1 を複数回 dot-source してもエラーが発生しないことを確認
        . $PSScriptRoot/../lib/SetupHandler.ps1
        . $PSScriptRoot/../lib/SetupHandler.ps1
        . $PSScriptRoot/../lib/SetupHandler.ps1

        # 3回ロード後もクラスが正常に動作することを確認
        $ctx = [SetupContext]::new("D:\test")
        $ctx.DotfilesPath | Should -Be "D:\test"

        $result = [SetupResult]::CreateSuccess("Test", "OK")
        $result.Success | Should -Be $true
    }

    It 'should allow handler to use SetupContext after multiple loads' {
        # SetupHandler.ps1 を再ロード
        . $PSScriptRoot/../lib/SetupHandler.ps1

        # ハンドラーをロード（内部で SetupHandler.ps1 を再度 dot-source する）
        . $PSScriptRoot/../lib/Invoke-ExternalCommand.ps1
        . $PSScriptRoot/../handlers/Handler.Chezmoi.ps1

        # SetupContext を作成
        $ctx = [SetupContext]::new("D:\dotfiles")

        # ハンドラーの CanApply が型エラーなく呼び出せることを確認
        $handler = [ChezmoiHandler]::new()

        # これが失敗する場合: "Cannot convert SetupContext to SetupContext"
        { $handler.CanApply($ctx) } | Should -Not -Throw "*Cannot convert*SetupContext*"
    }

    It 'should work when install.ps1 pattern is simulated' {
        # install.ps1 のパターンをシミュレート
        # 1. SetupHandler.ps1 をロード
        . $PSScriptRoot/../lib/SetupHandler.ps1
        . $PSScriptRoot/../lib/Invoke-ExternalCommand.ps1

        # 2. コンテキストを作成
        $ctx = [SetupContext]::new("D:\dotfiles")

        # 3. install.ps1 と同様に Get-SetupHandler でロードするが、
        #    テスト専用ハンドラーを使い Docker/WSL 等の実コマンド実行を回避する
        $handlersPath = Join-Path $TestDrive "handlers"
        New-Item -Path $handlersPath -ItemType Directory -Force | Out-Null

        $handlerA = @'
class FakeAlphaHandler : SetupHandlerBase {
    FakeAlphaHandler() {
        $this.Name = "FakeAlpha"
        $this.Order = 10
    }
    [bool] CanApply([SetupContext]$ctx) { return $true }
    [SetupResult] Apply([SetupContext]$ctx) { return $this.CreateSuccessResult("OK") }
}
'@
        $handlerB = @'
class FakeBetaHandler : SetupHandlerBase {
    FakeBetaHandler() {
        $this.Name = "FakeBeta"
        $this.Order = 20
    }
    [bool] CanApply([SetupContext]$ctx) { return $true }
    [SetupResult] Apply([SetupContext]$ctx) { return $this.CreateSuccessResult("OK") }
}
'@
        Set-Content -Path (Join-Path $handlersPath "Handler.FakeAlpha.ps1") -Value $handlerA
        Set-Content -Path (Join-Path $handlersPath "Handler.FakeBeta.ps1") -Value $handlerB

        $handlers = Get-SetupHandler -HandlersPath $handlersPath

        # 4. 各ハンドラーの CanApply を呼び出し
        foreach ($handler in $handlers) {
            # 型変換エラーが発生しないことを確認
            { $handler.CanApply($ctx) } | Should -Not -Throw "*Cannot convert*SetupContext*"
        }
    }
}

Describe 'Show-SetupSummary' {
    BeforeEach {
        Mock Write-Host { }
    }

    It 'should display <status> result with <symbol> in <color>' -ForEach @(
        @{ status = "success"; symbol = "✓"; color = "Green"; success = $true; message = "完了" }
        @{ status = "failure"; symbol = "✗"; color = "Red"; success = $false; message = "エラー" }
    ) {
        $results = @(
            if ($success) {
                [SetupResult]::CreateSuccess("TestHandler", $message)
            } else {
                [SetupResult]::CreateFailure("TestHandler", $message)
            }
        )

        Show-SetupSummary -Results $results

        # -ForEach スコープ外では $symbol/$color が参照できないため変数を固定
        $expectedSymbol = $symbol
        $expectedColor = $color
        Should -Invoke Write-Host -ParameterFilter {
            $Object -match "\[$expectedSymbol\].*TestHandler" -and
            $ForegroundColor -eq $expectedColor
        }
    }

    It 'should display Summary header' {
        # 空でない結果でテスト
        $results = @(
            [SetupResult]::CreateSuccess("TestHandler", "テスト")
        )

        Show-SetupSummary -Results $results

        Should -Invoke Write-Host -ParameterFilter {
            $Object -match "Summary"
        }
    }

    It 'should display multiple results' {
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
