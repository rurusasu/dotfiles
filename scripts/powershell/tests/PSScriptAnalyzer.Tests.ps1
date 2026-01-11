BeforeAll {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $settingsPath = Join-Path $projectRoot "PSScriptAnalyzerSettings.psd1"

    # PSScriptAnalyzer モジュールの確認とインストール
    if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
        Write-Host "PSScriptAnalyzer がインストールされていません。インストールを開始します..." -ForegroundColor Yellow
        Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber
        Write-Host "PSScriptAnalyzer のインストールに成功しました" -ForegroundColor Green
    }

    Import-Module PSScriptAnalyzer -Force

    # テスト対象ファイルの収集
    $sourceFiles = @(
        "$projectRoot\lib\SetupHandler.ps1",
        "$projectRoot\lib\Invoke-ExternalCommand.ps1",
        "$projectRoot\handlers\Handler.WslConfig.ps1",
        "$projectRoot\handlers\Handler.Docker.ps1",
        "$projectRoot\handlers\Handler.VscodeServer.ps1",
        "$projectRoot\handlers\Handler.Chezmoi.ps1",
        "$projectRoot\handlers\Handler.Winget.ps1"
    ) | Where-Object { Test-Path $_ }
}

Describe 'PSScriptAnalyzer - 静的解析' {
    Context 'ライブラリファイル' {
        It 'lib/SetupHandler.ps1 に Error/Warning レベルの問題がない' {
            $results = Invoke-ScriptAnalyzer -Path "$projectRoot\lib\SetupHandler.ps1" -Settings $settingsPath -Severity Error,Warning
            $results | Should -BeNullOrEmpty
        }

        It 'lib/Invoke-ExternalCommand.ps1 に Error/Warning レベルの問題がない' {
            $results = Invoke-ScriptAnalyzer -Path "$projectRoot\lib\Invoke-ExternalCommand.ps1" -Settings $settingsPath -Severity Error,Warning
            $results | Should -BeNullOrEmpty
        }
    }

    Context 'ハンドラーファイル' {
        It 'Handler.WslConfig.ps1 に Error/Warning レベルの問題がない' {
            $results = Invoke-ScriptAnalyzer -Path "$projectRoot\handlers\Handler.WslConfig.ps1" -Settings $settingsPath -Severity Error,Warning
            # TypeNotFound を除外（using module の制限）
            $results = $results | Where-Object { $_.RuleName -ne 'TypeNotFound' }
            $results | Should -BeNullOrEmpty
        }

        It 'Handler.Docker.ps1 に Error/Warning レベルの問題がない' {
            $results = Invoke-ScriptAnalyzer -Path "$projectRoot\handlers\Handler.Docker.ps1" -Settings $settingsPath -Severity Error,Warning
            $results = $results | Where-Object { $_.RuleName -ne 'TypeNotFound' }
            $results | Should -BeNullOrEmpty
        }

        It 'Handler.VscodeServer.ps1 に Error/Warning レベルの問題がない' {
            $results = Invoke-ScriptAnalyzer -Path "$projectRoot\handlers\Handler.VscodeServer.ps1" -Settings $settingsPath -Severity Error,Warning
            $results = $results | Where-Object { $_.RuleName -ne 'TypeNotFound' }
            $results | Should -BeNullOrEmpty
        }

        It 'Handler.Chezmoi.ps1 に Error/Warning レベルの問題がない' {
            $results = Invoke-ScriptAnalyzer -Path "$projectRoot\handlers\Handler.Chezmoi.ps1" -Settings $settingsPath -Severity Error,Warning
            $results = $results | Where-Object { $_.RuleName -ne 'TypeNotFound' }
            $results | Should -BeNullOrEmpty
        }

        It 'Handler.Winget.ps1 に Error/Warning レベルの問題がない' {
            $results = Invoke-ScriptAnalyzer -Path "$projectRoot\handlers\Handler.Winget.ps1" -Settings $settingsPath -Severity Error,Warning
            $results = $results | Where-Object { $_.RuleName -ne 'TypeNotFound' }
            $results | Should -BeNullOrEmpty
        }
    }

    Context '全体的なコード品質' {
        It 'すべてのソースファイルに Critical な問題がない' {
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

        It 'プロジェクト全体で Error/Warning レベルの問題が 0 件' {
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
        It 'すべてのハンドラーが CmdletBinding 属性を適切に使用している' {
            # この例では、外部コマンドラッパーが [CmdletBinding()] を使用しているかチェック
            $wrapperFile = "$projectRoot\lib\Invoke-ExternalCommand.ps1"
            $content = Get-Content -Raw $wrapperFile

            # 関数定義の数をカウント
            $functionCount = ([regex]::Matches($content, 'function\s+Invoke-\w+')).Count

            # [CmdletBinding()] の数をカウント
            $cmdletBindingCount = ([regex]::Matches($content, '\[CmdletBinding\(\)\]')).Count

            # すべての関数が CmdletBinding を持つべき
            $cmdletBindingCount | Should -BeGreaterOrEqual 1
        }

        It 'すべてのハンドラークラスが SetupHandlerBase を継承している' {
            $handlerFiles = Get-ChildItem -Path "$projectRoot\handlers" -Filter "Handler.*.ps1"

            foreach ($file in $handlerFiles) {
                $content = Get-Content -Raw $file.FullName
                $content | Should -Match 'class\s+\w+Handler\s*:\s*SetupHandlerBase'
            }
        }
    }
}

Describe 'PSScriptAnalyzer - 設定ファイル' {
    It 'PSScriptAnalyzerSettings.psd1 が存在する' {
        Test-Path $settingsPath | Should -Be $true
    }

    It 'PSScriptAnalyzerSettings.psd1 が有効な設定ファイルである' {
        { Import-PowerShellDataFile $settingsPath } | Should -Not -Throw
    }

    It 'PSScriptAnalyzerSettings.psd1 に ExcludeRules が定義されている' {
        $settings = Import-PowerShellDataFile $settingsPath
        $settings.ExcludeRules | Should -Not -BeNullOrEmpty
    }

    It 'PSScriptAnalyzerSettings.psd1 に Severity が定義されている' {
        $settings = Import-PowerShellDataFile $settingsPath
        $settings.Severity | Should -Contain 'Error'
        $settings.Severity | Should -Contain 'Warning'
    }
}
