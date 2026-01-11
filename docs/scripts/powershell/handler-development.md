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

**テンプレート**:

```powershell
BeforeAll {
    . "$PSScriptRoot\..\..\lib\SetupHandler.ps1"
    . "$PSScriptRoot\..\..\lib\Invoke-ExternalCommand.ps1"
    . "$PSScriptRoot\..\..\handlers\Handler.YourName.ps1"
}

Describe 'YourNameHandler' {
    Context 'Constructor' {
        It 'プロパティが正しく初期化される' {
            $handler = [YourNameHandler]::new()

            $handler.Name | Should -Be "YourName"
            $handler.Description | Should -Not -BeNullOrEmpty
            $handler.Order | Should -Be 50
        }
    }

    Context 'CanApply' {
        It 'ファイルが存在する場合は true を返す' {
            Mock Invoke-TestPath { return $true }

            $handler = [YourNameHandler]::new()
            $context = [SetupContext]::new("C:\test")

            $result = $handler.CanApply($context)
            $result | Should -Be $true
        }

        It 'ファイルが存在しない場合は false を返す' {
            Mock Invoke-TestPath { return $false }

            $handler = [YourNameHandler]::new()
            $context = [SetupContext]::new("C:\test")

            $result = $handler.CanApply($context)
            $result | Should -Be $false
        }
    }

    Context 'Apply' {
        It 'コマンドを実行して成功を返す' {
            Mock Invoke-YourCommand { return "Success output" }

            $handler = [YourNameHandler]::new()
            $context = [SetupContext]::new("C:\test")

            $result = $handler.Apply($context)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "成功"
            Should -Invoke Invoke-YourCommand -Times 1 -Exactly
        }

        It 'エラー発生時は失敗を返す' {
            Mock Invoke-YourCommand { throw "Command failed" }

            $handler = [YourNameHandler]::new()
            $context = [SetupContext]::new("C:\test")

            $result = $handler.Apply($context)

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

- [Handler.WslConfig.ps1](../../../scripts/powershell/handlers/Handler.WslConfig.ps1) - VHD拡張、ファイルシステムリサイズ
- [Handler.Docker.ps1](../../../scripts/powershell/handlers/Handler.Docker.ps1) - Docker Desktop連携
- [Handler.VscodeServer.ps1](../../../scripts/powershell/handlers/Handler.VscodeServer.ps1) - VS Code Server管理
- [Handler.Chezmoi.ps1](../../../scripts/powershell/handlers/Handler.Chezmoi.ps1) - dotfiles適用
- [Handler.Winget.ps1](../../../scripts/powershell/handlers/Handler.Winget.ps1) - wingetパッケージ管理
