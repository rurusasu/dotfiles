BeforeDiscovery {
    # ファイルごとのケースを Discovery で確定し、解析は Run で一度だけ行う。
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $sourceCases = @(
        Get-ChildItem -Path "$projectRoot\lib" -Filter "*.ps1" -ErrorAction SilentlyContinue
        Get-ChildItem -Path "$projectRoot\handlers" -Filter "Handler.*.ps1" -ErrorAction SilentlyContinue
    ) | ForEach-Object {
        $relativePath = "$($_.Directory.Name)\$($_.Name)"
        @{
            RelativePath = $relativePath
            # この 2 ファイルは従来どおり TypeNotFound も失敗にする。
            IgnoreTypeNotFound = $relativePath -notin @(
                'lib\SetupHandler.ps1'
                'lib\Invoke-ExternalCommand.ps1'
            )
        }
    }
}

BeforeAll {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $settingsPath = Join-Path $projectRoot "PSScriptAnalyzerSettings.psd1"

    # PSScriptAnalyzer モジュールの確認と自動インストール
    if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer | Where-Object { $_.Version -eq ([version]'1.22.0') })) {
        Write-Host "PSScriptAnalyzer 1.22.0 をインストールしています..." -ForegroundColor Yellow
        try {
            Install-Module -Name PSScriptAnalyzer -RequiredVersion 1.22.0 -Scope CurrentUser -Force -ErrorAction Stop
        }
        catch {
            throw "PSScriptAnalyzer の自動インストールに失敗しました: $($_.Exception.Message). 手動でインストールしてください: Install-Module PSScriptAnalyzer -RequiredVersion 1.22.0 -Scope CurrentUser -Force"
        }
    }

    try {
        Import-Module PSScriptAnalyzer -RequiredVersion 1.22.0 -Force -ErrorAction Stop
    }
    catch {
        throw "PSScriptAnalyzer 1.22.0 のインポートに失敗しました: $($_.Exception.Message)"
    }

    # Run フェーズ用に再収集（BeforeDiscovery で収集済みの変数はフェーズをまたいで引き継がれない）
    $sourceFiles = @(
        Get-ChildItem -Path "$projectRoot\lib" -Filter "*.ps1" -ErrorAction SilentlyContinue
        Get-ChildItem -Path "$projectRoot\handlers" -Filter "Handler.*.ps1" -ErrorAction SilentlyContinue
    ) | Select-Object -ExpandProperty FullName

    if ($sourceFiles.Count -eq 0) {
        throw "ソースファイルが見つかりません (lib/ または handlers/ が存在しない可能性があります)。静的解析対象がゼロの状態は成功扱いできません。"
    }

    foreach ($requiredFile in @('lib\SetupHandler.ps1', 'lib\Invoke-ExternalCommand.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $requiredFile) -PathType Leaf)) {
            throw "必須の静的解析対象が見つかりません: $requiredFile"
        }
    }
}

Describe 'PSScriptAnalyzer - 静的解析' {
    Context 'ソースファイルのコード品質' {
        It 'should have no Error/Warning in <RelativePath>' -ForEach $sourceCases {
            $results = @(Invoke-ScriptAnalyzer -Path (Join-Path $projectRoot $RelativePath) -Settings $settingsPath -Severity Error, Warning -ErrorAction Stop)
            if ($IgnoreTypeNotFound) {
                # TypeNotFound を除外（using module の制限）
                $results = @($results | Where-Object { $_.RuleName -ne 'TypeNotFound' })
            }

            $issues = @($results | ForEach-Object {
                    "$($_.ScriptName):$($_.Line) - [$($_.Severity)] $($_.RuleName): $($_.Message)"
                })
            $issues | Should -BeNullOrEmpty
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
