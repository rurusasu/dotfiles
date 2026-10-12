#Requires -Module Pester

<#
.SYNOPSIS
    セットアップ結果表示のテスト
#>

BeforeAll {
    . $PSScriptRoot/../lib/SetupHandler.ps1
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
            }
            else {
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
