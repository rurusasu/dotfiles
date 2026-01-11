# テスト

## Pester v5 の強制使用

### テストランナー

[tests/Invoke-Tests.ps1](../../../scripts/powershell/tests/Invoke-Tests.ps1)

### 重要な設定

```powershell
# 1. Pester v3 自動削除
if (Get-Module -Name Pester) {
    $currentVersion = (Get-Module -Name Pester).Version
    if ($currentVersion -lt [Version]"5.0.0") {
        Remove-Module -Name Pester -Force -ErrorAction SilentlyContinue
    }
}

# 2. Pester v5 自動インストール
$pesterV5 = Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge [Version]"5.0.0" }
if (-not $pesterV5) {
    Install-Module -Name Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber
}

# 3. Pester v5 強制ロード
Import-Module -Name Pester -MinimumVersion 5.0.0 -Force

# 4. カバレッジでモックを有効化
$pesterConfig.CodeCoverage.UseBreakpoints = $false
```

**重要**: `UseBreakpoints = $false` を設定しないと、カバレッジ有効時にモックが正しく動作しません

## テスト実行

```powershell
# tests/ ディレクトリに移動
cd scripts/powershell/tests

# 全テスト実行（カバレッジなし、高速）
.\Invoke-Tests.ps1 -MinimumCoverage 0

# 全テスト + カバレッジ（80%以上を要求）
.\Invoke-Tests.ps1

# カバレッジしきい値を変更
.\Invoke-Tests.ps1 -MinimumCoverage 90

# 特定のテストファイルのみ
.\Invoke-Tests.ps1 -Path .\Install.Tests.ps1 -MinimumCoverage 0

# カバレッジ詳細表示
.\Invoke-Tests.ps1 -ShowCoverage
```

**現在の状態**: 203/203 テスト成功（100%）、カバレッジ 95%+

## テストパターン

### 1. ハンドラーテスト

**参考**: [tests/handlers/Handler.Chezmoi.Tests.ps1](../../../scripts/powershell/tests/handlers/Handler.Chezmoi.Tests.ps1)

```powershell
BeforeAll {
    # ライブラリ読み込み
    . "$PSScriptRoot\..\..\lib\SetupHandler.ps1"
    . "$PSScriptRoot\..\..\lib\Invoke-ExternalCommand.ps1"
    . "$PSScriptRoot\..\..\handlers\Handler.Chezmoi.ps1"
}

Describe 'ChezmoiHandler' {
    Context 'Constructor' {
        It 'プロパティが正しく初期化される' {
            $handler = [ChezmoiHandler]::new()

            $handler.Name | Should -Be "Chezmoi"
            $handler.Description | Should -Not -BeNullOrEmpty
            $handler.Order | Should -Be 100
        }
    }

    Context 'CanApply' {
        It 'chezmoi が見つかる場合は true を返す' {
            # モックを設定
            Mock Invoke-TestPath { return $true }

            $handler = [ChezmoiHandler]::new()
            $context = [SetupContext]::new("C:\test")

            $result = $handler.CanApply($context)
            $result | Should -Be $true
        }

        It 'chezmoi が見つからない場合は false を返す' {
            Mock Invoke-TestPath { return $false }

            $handler = [ChezmoiHandler]::new()
            $context = [SetupContext]::new("C:\test")

            $result = $handler.CanApply($context)
            $result | Should -Be $false
        }
    }

    Context 'Apply' {
        It 'chezmoi apply を実行して成功を返す' {
            Mock Invoke-Chezmoi { return "Applied" }

            $handler = [ChezmoiHandler]::new()
            $context = [SetupContext]::new("C:\test")

            $result = $handler.Apply($context)

            $result.Success | Should -Be $true
            Should -Invoke Invoke-Chezmoi -Times 1
        }

        It 'エラー発生時は失敗を返す' {
            Mock Invoke-Chezmoi { throw "chezmoi error" }

            $handler = [ChezmoiHandler]::new()
            $context = [SetupContext]::new("C:\test")

            $result = $handler.Apply($context)

            $result.Success | Should -Be $false
            $result.Error | Should -Not -BeNullOrEmpty
        }
    }
}
```

### 2. オーケストレーターテスト

**参考**: [tests/Install.Tests.ps1](../../../scripts/powershell/tests/Install.Tests.ps1)

```powershell
Describe 'ハンドラーの動的ロード' {
    BeforeAll {
        $handlersPath = Join-Path $PSScriptRoot "..\handlers"
    }

    It '全ハンドラーがロードされる' {
        $handlers = @()
        $handlerFiles = Get-ChildItem -Path "$handlersPath" -Filter "Handler.*.ps1"

        foreach ($file in $handlerFiles) {
            . $file.FullName
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
            $className = $baseName.Replace("Handler.", "") + "Handler"
            $handlerInstance = New-Object $className
            $handlers += $handlerInstance
        }

        $handlers.Count | Should -BeGreaterThan 0
    }

    It 'Order プロパティでソートされる' {
        # テスト用ハンドラーを作成
        $handlers = @(
            [PSCustomObject]@{ Name = "A"; Order = 20 },
            [PSCustomObject]@{ Name = "B"; Order = 10 },
            [PSCustomObject]@{ Name = "C"; Order = 30 }
        )

        $sorted = $handlers | Sort-Object Order

        $sorted[0].Name | Should -Be "B"
        $sorted[1].Name | Should -Be "A"
        $sorted[2].Name | Should -Be "C"
    }

    It '空配列の場合は空の結果を返す' {
        $emptyArray = @() | Sort-Object Order
        @($emptyArray).Count | Should -Be 0
    }
}
```

## モックのベストプラクティス

### 1. 外部コマンドは必ずラッパー経由でモック

```powershell
Mock Invoke-Wsl { return "output" }
Mock Invoke-Chezmoi { return "success" }
```

### 2. ファイル操作もラッパー経由

```powershell
Mock Invoke-TestPath { return $true }
Mock Invoke-GetContent { return "content" }
```

### 3. Should -Invoke でモック呼び出しを検証

```powershell
Should -Invoke Invoke-Wsl -Times 1 -Exactly
Should -Invoke Invoke-Chezmoi -ParameterFilter { $ArgumentList -contains "apply" }
```

### 4. エラーハンドリングのテスト

```powershell
Mock Invoke-Wsl { throw "WSL error" }
$result = $handler.Apply($context)
$result.Success | Should -Be $false
$result.Error | Should -Not -BeNullOrEmpty
```

## トラブルシューティング

### 1. Pester v3 が自動ロードされる

**症状**: `Should` コマンドレットが見つからない、v5 の機能が使えない

**解決策**: Invoke-Tests.ps1 は自動的に v3 を削除して v5 をロードします

```powershell
# 手動で解決する場合
Remove-Module -Name Pester -Force -ErrorAction SilentlyContinue
Import-Module -Name Pester -MinimumVersion 5.0.0 -Force
```

### 2. カバレッジ有効時にテストが失敗する

**症状**: `-MinimumCoverage 0` だと成功するが、カバレッジ有効だと失敗する

**原因**: `UseBreakpoints = $true` によりモックが正しく動作しない

**解決策**: [tests/Invoke-Tests.ps1:134](../../../scripts/powershell/tests/Invoke-Tests.ps1#L134) で既に設定済み

```powershell
$pesterConfig.CodeCoverage.UseBreakpoints = $false
```

### 3. テストでモックが効かない

**原因**: 外部コマンドを直接呼び出している

**解決策**: ラッパー関数を使用する

```powershell
# ❌ 直接呼び出し（モック不可）
& wsl.exe --list

# ✅ ラッパー経由（モック可能）
Invoke-Wsl -ArgumentList "--list"

# テストでモック
Mock Invoke-Wsl { return "Mocked output" }
```

### 4. 空配列のプロパティアクセスエラー

**症状**: `PropertyNotFoundException: The property 'Count' cannot be found`

**解決策**: `@()` でラップする

```powershell
# ❌ エラーの可能性
$handlers = $handlers | Sort-Object Order
$handlers.Count

# ✅ 安全
$handlers = @($handlers | Sort-Object Order)
@($handlers).Count
```

## PSScriptAnalyzer 静的解析

### 概要

PSScriptAnalyzer による静的解析テストを [tests/PSScriptAnalyzer.Tests.ps1](../../../scripts/powershell/tests/PSScriptAnalyzer.Tests.ps1) で実施しています。

- **設定ファイル**: [PSScriptAnalyzerSettings.psd1](../../../scripts/powershell/PSScriptAnalyzerSettings.psd1)
- **検出レベル**: Error/Warning のみ(Information は除外)
- **テスト数**: 15 テスト(ライブラリ 2 + ハンドラー 5 + 全体 3 + ベストプラクティス 2 + 設定 3)

### 実行方法

```powershell
cd scripts/powershell/tests

# PSScriptAnalyzer テストのみ実行
.\Invoke-Tests.ps1 -Path .\PSScriptAnalyzer.Tests.ps1 -MinimumCoverage 0

# 全テストと一緒に実行
.\Invoke-Tests.ps1
```

### 設定ファイル

[PSScriptAnalyzerSettings.psd1](../../../scripts/powershell/PSScriptAnalyzerSettings.psd1) で除外ルールと重大度を設定:

```powershell
@{
    # 除外するルール
    ExcludeRules = @(
        # dot-source で読み込む型は静的解析で認識できないため除外
        'PSUseOutputTypeCorrectly',
        # BOM エンコーディングは UTF-8 (without BOM) でも問題ないため除外
        'PSUseBOMForUnicodeEncodedFile',
        # 外部コマンドラッパー関数では ShouldProcess は不要なため除外
        'PSUseShouldProcessForStateChangingFunctions'
    )

    # 重大度でフィルタリング(Information レベルを除外)
    # TypeNotFound は Information レベルで、using module の制限によるパースエラーなので無視
    Severity = @('Error', 'Warning')

    # 特定のルールの設定
    Rules = @{
        PSAvoidUsingCmdletAliases = @{
            allowlist = @()
        }
    }
}
```

### TypeNotFound について

`using module` ステートメントで読み込む型は、PSScriptAnalyzer が静的解析時に認識できないため、`TypeNotFound` 警告が出ます。これは Information レベルのため、Severity 設定で除外され、テストにも影響しません。

**理由**:
- `using module` は実行時に型を読み込む
- PSScriptAnalyzer は静的解析ツールでファイルを実行しない
- 実際には問題なく動作する

**対処法**:
- Severity を Error/Warning のみに設定(設定済み)
- テスト内で明示的にフィルタリング: `$results | Where-Object { $_.RuleName -ne 'TypeNotFound' }`

### 検出される問題例

PSScriptAnalyzer は以下のような問題を検出します:

1. **PSAvoidAssignmentToAutomaticVariable**: `$error` などの自動変数への代入
2. **PSUseSingularNouns**: 複数形の名詞を使用した関数名(例: `Test-PathExists` → `Test-PathExist`)
3. **PSUseDeclaredVarsMoreThanAssignments**: 未使用変数
4. **PSAvoidUsingCmdletAliases**: エイリアスの使用
5. **PSUseShouldProcessForStateChangingFunctions**: ShouldProcess の欠如(wrapper関数は除外)

### コードフォーマット

コードフォーマットは [treefmt.toml](../../../treefmt.toml) で管理されています:

```toml
[formatter.powershell]
command = "pwsh"
options = [
  "-NoProfile",
  "-Command",
  "& { $ErrorActionPreference = 'Stop'; if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) { Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber | Out-Null }; Import-Module PSScriptAnalyzer -Force; $content = Get-Content -Raw -LiteralPath $env:FILENAME; $formatted = Invoke-Formatter -ScriptDefinition $content; Set-Content -LiteralPath $env:FILENAME -Value $formatted -Encoding utf8 }"
]
includes = ["*.ps1"]
```

**注意**:
- `Invoke-Formatter` はフォーマット(スタイル)
- `Invoke-ScriptAnalyzer` はリント(コード品質)
- 両者は別の目的を持つツールです
