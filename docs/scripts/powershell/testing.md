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

**現在の状態**: 230+ テスト成功（100%）、カバレッジ 95%+

## pre-commit 統合

PowerShell ファイルの変更時に自動でテストが実行されます。

**設定ファイル**: [.pre-commit-config.yaml](../../../.pre-commit-config.yaml)

```yaml
- repo: local
  hooks:
    - id: powershell-tests
      name: powershell tests
      entry: pwsh -NoProfile -Command "& ./scripts/powershell/tests/Invoke-Tests.ps1 -MinimumCoverage 80"
      language: system
      pass_filenames: false
      types: [powershell]
```

**実行方法**:

```bash
# PowerShell テストのみ
pre-commit run powershell-tests --all-files

# 全フックを実行
pre-commit run --all-files
```

## テスト命名規則（ベストプラクティス）

### It ブロックの命名

`It` ブロック名は `'should ...'` で始めます（英語、小文字）。

```powershell
# ✅ 正しい
It 'should return true when path exists' { }
It 'should throw exception when file not found' { }
It 'should set <property> to <expected>' { }

# ❌ 誤り
It 'パスが存在する場合は true を返す' { }  # 日本語
It 'Returns true when path exists' { }        # 大文字始まり
It 'true を返す' { }                          # 説明不足
```

### -ForEach によるパラメタライズ

類似テストは `-ForEach` でパラメタライズします（pytest の `@pytest.mark.parametrize` と同様）。

```powershell
# ✅ 正しい（パラメタライズ）
It 'should set <property> to <expected>' -ForEach @(
    @{ property = "Name"; expected = "Docker" }
    @{ property = "Description"; expected = "Docker Desktop WSL 連携" }
    @{ property = "Order"; expected = 20 }
    @{ property = "RequiresAdmin"; expected = $false }
) {
    $handler.$property | Should -Be $expected
}

# ❌ 誤り（個別テスト）
It 'should set Name to Docker' {
    $handler.Name | Should -Be "Docker"
}
It 'should set Order to 20' {
    $handler.Order | Should -Be 20
}
```

### トークン置換

`-ForEach` でハッシュテーブルを渡すと、`<key>` 形式のトークンがテスト名で自動置換されます。

```powershell
# テスト名: "should set Name to Docker"
#           "should set Order to 20"
It 'should set <property> to <expected>' -ForEach @(
    @{ property = "Name"; expected = "Docker" }
    @{ property = "Order"; expected = 20 }
) {
    $handler.$property | Should -Be $expected
}
```

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
    BeforeEach {
        $script:handler = [ChezmoiHandler]::new()
        $script:ctx = [SetupContext]::new("D:\dotfiles")
    }

    Context 'Constructor' {
        # パラメタライズされたテスト
        It 'should set <property> to <expected>' -ForEach @(
            @{ property = "Name"; expected = "Chezmoi" }
            @{ property = "Description"; expected = "chezmoi による dotfiles 適用" }
            @{ property = "Order"; expected = 100 }
            @{ property = "RequiresAdmin"; expected = $false }
        ) {
            $handler.$property | Should -Be $expected
        }
    }

    Context 'CanApply' {
        It 'should return true when chezmoi is found' {
            Mock Get-ExternalCommand { return @{ Source = "chezmoi.exe" } }

            $result = $handler.CanApply($ctx)
            $result | Should -Be $true
        }

        It 'should return false when chezmoi is not found' {
            Mock Get-ExternalCommand { return $null }

            $result = $handler.CanApply($ctx)
            $result | Should -Be $false
        }
    }

    Context 'Apply' {
        It 'should return success when chezmoi apply succeeds' {
            Mock Invoke-Chezmoi { return "Applied" }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            Should -Invoke Invoke-Chezmoi -Times 1
        }

        It 'should return failure when exception is thrown' {
            Mock Invoke-Chezmoi { throw "chezmoi error" }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Error | Should -Not -BeNullOrEmpty
        }
    }
}
```

### 2. オーケストレーターテスト

**参考**: [tests/Install.Tests.ps1](../../../scripts/powershell/tests/Install.Tests.ps1)

```powershell
Describe 'Handler dynamic loading' {
    BeforeAll {
        $handlersPath = Join-Path $PSScriptRoot "..\handlers"
    }

    It 'should load all handlers' {
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

    It 'should sort handlers by Order property' {
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

    It 'should return empty array when no handlers exist' {
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
