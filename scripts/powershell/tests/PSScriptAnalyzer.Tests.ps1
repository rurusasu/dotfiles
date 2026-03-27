BeforeAll {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $settingsPath = Join-Path $projectRoot "PSScriptAnalyzerSettings.psd1"

    # PSScriptAnalyzer モジュールの確認と自動インストール
    if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
        Write-Host "PSScriptAnalyzer をインストールしています..." -ForegroundColor Yellow
        try {
            Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force -SkipPublisherCheck
        } catch {
            throw "PSScriptAnalyzer の自動インストールに失敗しました: $($_.Exception.Message). 手動でインストールしてください: Install-Module PSScriptAnalyzer -Scope CurrentUser -Force"
        }
    }

    Import-Module PSScriptAnalyzer -Force

    # テスト対象ファイルの収集（動的に検出）
    $sourceFiles = @(
        Get-ChildItem -Path "$projectRoot\lib" -Filter "*.ps1" -ErrorAction SilentlyContinue
        Get-ChildItem -Path "$projectRoot\handlers" -Filter "Handler.*.ps1" -ErrorAction SilentlyContinue
    ) | Select-Object -ExpandProperty FullName
}

Describe 'PSScriptAnalyzer - 静的解析' {
    Context 'ライブラリファイル' {
        It 'should have no Error/Warning in <_>' -ForEach @(
            "lib\SetupHandler.ps1",
            "lib\Invoke-ExternalCommand.ps1"
        ) {
            $results = Invoke-ScriptAnalyzer -Path "$projectRoot\$_" -Settings $settingsPath -Severity Error,Warning
            $results | Should -BeNullOrEmpty
        }
    }

    Context 'ハンドラーファイル' {
        It 'should have no Error/Warning in <_>' -ForEach @(
            (Get-ChildItem -Path "$((Split-Path -Parent $PSScriptRoot))\handlers" -Filter "Handler.*.ps1" -ErrorAction SilentlyContinue |
                ForEach-Object { "handlers\$($_.Name)" })
        ) {
            $results = Invoke-ScriptAnalyzer -Path "$projectRoot\$_" -Settings $settingsPath -Severity Error,Warning
            # TypeNotFound を除外（using module の制限）
            $results = $results | Where-Object { $_.RuleName -ne 'TypeNotFound' }
            $results | Should -BeNullOrEmpty
        }
    }

    Context '全体的なコード品質' {
        It 'should have no Critical issues in all source files' {
            $allResults = @()
            foreach ($file in $sourceFiles) {
                $results = Invoke-ScriptAnalyzer -Path $file -Settings $settingsPath -Severity Error
                # TypeNotFound を除外（using module の制限）
                $results = $results | Where-Object { $_.RuleName -ne 'TypeNotFound' }
                $allResults += $results
            }

            if ($allResults.Count -gt 0) {
                $errorMessage = "Critical な問題が見つかりました:`n"
                foreach ($result in $allResults) {
                    $errorMessage += "  - $($result.ScriptName):$($result.Line) - $($result.RuleName): $($result.Message)`n"
                }
                throw $errorMessage
            }

            $allResults | Should -BeNullOrEmpty
        }

        It 'should have 0 Error/Warning issues in the entire project' {
            $allResults = @()
            foreach ($file in $sourceFiles) {
                $results = Invoke-ScriptAnalyzer -Path $file -Settings $settingsPath -Severity Error,Warning
                # TypeNotFound を除外（using module の制限）
                $results = $results | Where-Object { $_.RuleName -ne 'TypeNotFound' }
                $allResults += $results
            }

            if ($allResults.Count -gt 0) {
                $errorMessage = "Error/Warning レベルの問題が見つかりました:`n"
                foreach ($result in $allResults) {
                    $errorMessage += "  - $($result.ScriptName):$($result.Line) - [$($result.Severity)] $($result.RuleName): $($result.Message)`n"
                }
                Write-Host $errorMessage -ForegroundColor Yellow
            }

            $allResults.Count | Should -Be 0
        }
    }

    Context 'ベストプラクティス' {
        It 'should have at least one CmdletBinding attribute in wrapper file' {
            $wrapperFile = "$projectRoot\lib\Invoke-ExternalCommand.ps1"
            $content = Get-Content -Raw $wrapperFile

            # [CmdletBinding()] の数をカウント
            $cmdletBindingCount = ([regex]::Matches($content, '\[CmdletBinding\(\)\]')).Count

            $cmdletBindingCount | Should -BeGreaterOrEqual 1
        }

        It 'should have all handler classes inherit from SetupHandlerBase' {
            $handlerFiles = Get-ChildItem -Path "$projectRoot\handlers" -Filter "Handler.*.ps1"

            foreach ($file in $handlerFiles) {
                $content = Get-Content -Raw $file.FullName
                $content | Should -Match 'class\s+\w+Handler\s*:\s*SetupHandlerBase'
            }
        }
    }
}

Describe 'PSScriptAnalyzer - 設定ファイル' {
    It 'should exist at expected path' {
        Test-Path $settingsPath | Should -Be $true
    }

    It 'should be a valid PowerShell data file' {
        { Import-PowerShellDataFile $settingsPath } | Should -Not -Throw
    }

    It 'should have ExcludeRules defined' {
        $settings = Import-PowerShellDataFile $settingsPath
        $settings.ExcludeRules | Should -Not -BeNullOrEmpty
    }

    It 'should have <severity> in Severity list' -ForEach @(
        @{ severity = "Error" }
        @{ severity = "Warning" }
    ) {
        $settings = Import-PowerShellDataFile $settingsPath
        $settings.Severity | Should -Contain $severity
    }
}
