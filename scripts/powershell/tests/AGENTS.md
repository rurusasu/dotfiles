# Tests

Purpose: PowerShell ユニットテストのガイドライン

## テストフレームワーク

- **Pester 5.x**: PowerShell 用テストフレームワーク
- **bats**: Bash Automated Testing System（シェルスクリプト用）
- **カバレッジ目標**: 80% 以上（現在 99.13%）

## ディレクトリ構造

```
scripts/powershell/tests/   # メインテストディレクトリ
├── AGENTS.md               # このファイル
├── Invoke-Tests.ps1        # 統合テストランナー（Pester + bats）
├── Integration.Tests.ps1   # インテグレーションテスト（Windows/NixOS ツール存在確認）
├── handlers/               # ハンドラーテスト
│   ├── Handler.Chezmoi.Tests.ps1
│   ├── Handler.Docker.Tests.ps1
│   ├── Handler.VscodeServer.Tests.ps1
│   └── Handler.WslConfig.Tests.ps1
└── lib/                    # ライブラリテスト
    ├── Invoke-ExternalCommand.Tests.ps1
    └── SetupHandler.Tests.ps1
```

## テスト実行

```powershell
# Taskfile 経由（推奨）
task test:powershell  # PSScriptAnalyzer lint + Pester tests + bats tests

# 直接実行
cd scripts/powershell/tests

# 全テスト（全ディレクトリ + bats）
.\Invoke-Tests.ps1 -All -IncludeBats

# デフォルト（このディレクトリのみ）
.\Invoke-Tests.ps1

# カバレッジなし（高速）
.\Invoke-Tests.ps1 -MinimumCoverage 0

# 特定のテストファイルのみ
.\Invoke-Tests.ps1 -Path .\handlers\Handler.Docker.Tests.ps1
```

## Invoke-Tests.ps1 パラメータ

| パラメータ         | 説明                                                   |
| ------------------ | ------------------------------------------------------ |
| `-Path`            | テストパス（複数指定可）                               |
| `-All`             | 全テストディレクトリを実行（scripts/powershell/tests） |
| `-IncludeBats`     | bats テストも実行                                      |
| `-MinimumCoverage` | 最小カバレッジ % （デフォルト: 80）                    |
| `-ShowCoverage`    | 詳細カバレッジレポートを表示                           |

## カバレッジから除外されるコード

以下のコードはユニットテストでカバー不可能です（外部コマンド/ファイルシステム操作）：

| ファイル                         | 行  | コード                       | 理由                        |
| -------------------------------- | --- | ---------------------------- | --------------------------- |
| `lib/Invoke-ExternalCommand.ps1` | 53  | `if ($ExePath)`              | 外部exe呼び出しの分岐判定   |
| `lib/Invoke-ExternalCommand.ps1` | 54  | `& $ExePath @Arguments`      | 指定パスの chezmoi.exe 実行 |
| `lib/Invoke-ExternalCommand.ps1` | 56  | `& chezmoi @Arguments`       | PATH 内の chezmoi 実行      |
| `lib/Invoke-ExternalCommand.ps1` | 101 | `Set-Content ... -NoNewline` | 実際のファイル書き込み      |

これらは**統合テスト**でのみカバー可能です。

## モック戦略

### 外部コマンドのモック

`lib/Invoke-ExternalCommand.ps1` のラッパー関数を使用してモック可能にしています：

```powershell
# Bad: 直接呼び出し（モック不可）
& wsl --list --quiet

# Good: ラッパー関数経由（モック可能）
Invoke-Wsl --list --quiet
```

テストでのモック例：

```powershell
Mock Invoke-Wsl {
    param($Arguments)
    $argStr = $Arguments -join " "
    if ($argStr -match "whoami") {
        $global:LASTEXITCODE = 0
        return "testuser"
    }
    return ""
}
```

### Should -Invoke の注意点

Pester 5.x では `Should -Invoke` はパイプライン入力を受け付けません。
変数トラッキングパターンを使用してください：

```powershell
# Bad: パイプラインで使用
Should -Invoke Invoke-Wsl -Times 1

# Good: 変数トラッキング
$script:wslCalled = $false
Mock Invoke-Wsl { $script:wslCalled = $true }

$handler.Apply($ctx)

$script:wslCalled | Should -Be $true
```

## テスト作成ガイドライン

1. **各ハンドラーに対応するテストファイルを作成**
   - `Handler.*.ps1` → `Handler.*.Tests.ps1`

2. **Context でグループ化**
   - コンストラクタ、CanApply、Apply、各メソッドごとに Context を分ける

3. **BeforeEach で状態をリセット**
   - `$script:handler` と `$script:ctx` を毎回初期化

4. **すべての分岐パスをテスト**
   - 成功パス、失敗パス、エッジケースをカバー

5. **日本語でテスト名を記述**
   - 何をテストしているか明確にする
