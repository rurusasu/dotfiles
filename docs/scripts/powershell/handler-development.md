# ハンドラー開発ガイド

## 新しいハンドラーの作成

### ステップ 1: ハンドラーファイルの作成

**ファイル名**: `handlers/Handler.YourName.ps1`

**テンプレート**:

```powershell
using module ..\lib\SetupHandler.ps1

class YourNameHandler : SetupHandlerBase {
    YourNameHandler() {
        $this.Name = "YourName"
        $this.Description = "Your handler description"
        $this.Order = 50  # 既存ハンドラーの間に挿入する場合は 10 刻みで設定
    }

    [bool] CanApply([SetupContext]$context) {
        # 実行可否を判定
        # 例: 必要なファイルの存在確認、環境変数チェックなど
        $someFile = Join-Path $context.RootPath "some-file.txt"
        return (Invoke-TestPath $someFile)
    }

    [SetupResult] Apply([SetupContext]$context) {
        try {
            $this.WriteInfo("処理を開始します")

            # 外部コマンドはラッパー経由で実行（テスト可能）
            $output = Invoke-SomeCommand -ArgumentList "arg1", "arg2"

            # 共有データの設定（他のハンドラーで使用可能）
            $context.SharedData["YourName_Result"] = $output

            $this.WriteSuccess("処理が完了しました")
            return $this.CreateSuccessResult("成功: $output")

        } catch {
            $this.WriteError("エラーが発生しました: $($_.Exception.Message)")
            return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
        }
    }
}
```

### ステップ 2: 外部コマンドラッパーの追加（必要な場合）

**場所**: [lib/Invoke-ExternalCommand.ps1](../../../scripts/powershell/lib/Invoke-ExternalCommand.ps1)

```powershell
function Invoke-YourCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList
    )

    & your-command.exe @ArgumentList
}
```

### ステップ 3: テストファイルの作成

**ファイル名**: `tests/handlers/Handler.YourName.Tests.ps1`

**テンプレート**（[テスト命名規則](testing.md#テスト命名規則ベストプラクティス) に準拠）:

```powershell
BeforeAll {
    . "$PSScriptRoot\..\..\lib\SetupHandler.ps1"
    . "$PSScriptRoot\..\..\lib\Invoke-ExternalCommand.ps1"
    . "$PSScriptRoot\..\..\handlers\Handler.YourName.ps1"
}

Describe 'YourNameHandler' {
    BeforeEach {
        $script:handler = [YourNameHandler]::new()
        $script:ctx = [SetupContext]::new("D:\dotfiles")
    }

    Context 'Constructor' {
        # パラメタライズされたテスト（類似テストを -ForEach でまとめる）
        It 'should set <property> to <expected>' -ForEach @(
            @{ property = "Name"; expected = "YourName" }
            @{ property = "Description"; expected = "Your handler description" }
            @{ property = "Order"; expected = 50 }
            @{ property = "RequiresAdmin"; expected = $false }
        ) {
            $handler.$property | Should -Be $expected
        }
    }

    Context 'CanApply' {
        It 'should return true when file exists' {
            Mock Invoke-TestPath { return $true }

            $result = $handler.CanApply($ctx)
            $result | Should -Be $true
        }

        It 'should return false when file does not exist' {
            Mock Invoke-TestPath { return $false }

            $result = $handler.CanApply($ctx)
            $result | Should -Be $false
        }
    }

    Context 'Apply' {
        It 'should return success when command succeeds' {
            Mock Invoke-YourCommand { return "Success output" }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "成功"
            Should -Invoke Invoke-YourCommand -Times 1 -Exactly
        }

        It 'should return failure when exception is thrown' {
            Mock Invoke-YourCommand { throw "Command failed" }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Error | Should -Not -BeNullOrEmpty
        }
    }
}
```

### ステップ 4: テスト実行とカバレッジ確認

```powershell
cd tests
.\Invoke-Tests.ps1 -Path .\handlers\Handler.YourName.Tests.ps1 -MinimumCoverage 0
```

### ステップ 5: オーケストレーターへの自動統合

**不要**: install.ps1 は動的にハンドラーをロードするため、`Handler.*.ps1` パターンに一致すれば自動的に実行されます

## ハンドラー開発のチェックリスト

### 必須要件

- [ ] ファイル名が `Handler.{Name}.ps1` パターンに一致している
- [ ] クラス名が `{Name}Handler` 形式である
- [ ] `SetupHandlerBase` を継承している
- [ ] `Order` プロパティが設定されている（10刻み推奨）
- [ ] `CanApply()` メソッドを実装している
- [ ] `Apply()` メソッドを実装している
- [ ] エラーハンドリングを実装している（try-catch）

### テスト要件

- [ ] テストファイルが `tests/handlers/Handler.{Name}.Tests.ps1` に存在する
- [ ] Constructor のテストがある
- [ ] CanApply() のテストがある（true/false両方）
- [ ] Apply() の成功ケースのテストがある
- [ ] Apply() の失敗ケースのテストがある
- [ ] 外部コマンドがすべてモックされている
- [ ] テストが 100% パスする

### コード品質

- [ ] 外部コマンドをラッパー経由で実行している
- [ ] 冪等性が保証されている（何度実行しても同じ結果）
- [ ] ログ出力を適切に使用している（WriteInfo/WriteSuccess/WriteError）
- [ ] SharedData を適切に使用している（必要な場合）
- [ ] パス操作に Join-Path を使用している

## ハンドラーが動的ロードされない場合

### チェック項目

1. **ファイル名パターン**: `Handler.*.ps1` に一致しているか
   ```powershell
   # ✅ 正しい
   Handler.Docker.ps1

   # ❌ 誤り
   docker-handler.ps1
   MyHandler.ps1
   ```

2. **クラス名パターン**: `{Name}Handler` に一致しているか
   ```powershell
   # ✅ 正しい（Handler.Docker.ps1 の場合）
   class DockerHandler : SetupHandlerBase { }

   # ❌ 誤り
   class Docker : SetupHandlerBase { }
   class HandlerDocker : SetupHandlerBase { }
   ```

3. **基底クラス継承**: `SetupHandlerBase` を継承しているか
   ```powershell
   # ✅ 正しい
   class DockerHandler : SetupHandlerBase { }

   # ❌ 誤り
   class DockerHandler { }
   ```

4. **Order プロパティ**: コンストラクタで設定されているか
   ```powershell
   # ✅ 正しい
   DockerHandler() {
       $this.Order = 20
   }

   # ❌ 誤り（Order が未設定）
   DockerHandler() {
       $this.Name = "Docker"
   }
   ```

## 実装例

### 既存ハンドラーの参考実装

| ハンドラー | ソースファイル | テストファイル | 説明 |
|-----------|--------------|--------------|------|
| Winget | [Handler.Winget.ps1](../../../scripts/powershell/handlers/Handler.Winget.ps1) | [Handler.Winget.Tests.ps1](../../../scripts/powershell/tests/handlers/Handler.Winget.Tests.ps1) | winget パッケージ管理 |
| Chezmoi | [Handler.Chezmoi.ps1](../../../scripts/powershell/handlers/Handler.Chezmoi.ps1) | [Handler.Chezmoi.Tests.ps1](../../../scripts/powershell/tests/handlers/Handler.Chezmoi.Tests.ps1) | dotfiles 適用 |
| WslConfig | [Handler.WslConfig.ps1](../../../scripts/powershell/handlers/Handler.WslConfig.ps1) | [Handler.WslConfig.Tests.ps1](../../../scripts/powershell/tests/handlers/Handler.WslConfig.Tests.ps1) | VHD 拡張、FS リサイズ |
| Docker | [Handler.Docker.ps1](../../../scripts/powershell/handlers/Handler.Docker.ps1) | [Handler.Docker.Tests.ps1](../../../scripts/powershell/tests/handlers/Handler.Docker.Tests.ps1) | Docker Desktop 連携 |
| VscodeServer | [Handler.VscodeServer.ps1](../../../scripts/powershell/handlers/Handler.VscodeServer.ps1) | [Handler.VscodeServer.Tests.ps1](../../../scripts/powershell/tests/handlers/Handler.VscodeServer.Tests.ps1) | VS Code Server 管理 |
| NixOSWSL | [Handler.NixOSWSL.ps1](../../../scripts/powershell/handlers/Handler.NixOSWSL.ps1) | [Handler.NixOSWSL.Tests.ps1](../../../scripts/powershell/tests/handlers/Handler.NixOSWSL.Tests.ps1) | NixOS-WSL インストール |

### 関連ドキュメント

- [テスト](testing.md) - Pester v5 の使用方法とテストパターン
- [アーキテクチャ](architecture.md) - ハンドラーシステムの設計と実行フロー
- [コーディング規約](coding-standards.md) - 命名規則、スタイル、ベストプラクティス
