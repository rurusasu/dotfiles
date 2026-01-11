# 重要な原則

## 1. 冪等性（Idempotency）

### 定義

ハンドラーは何度実行しても同じ結果になるべきです。同じ環境で2回実行しても、1回目と2回目で同じ最終状態になります。

### 実装パターン

```powershell
[SetupResult] Apply([SetupContext]$context) {
    try {
        # 既に適用済みかチェック
        if ($this.IsAlreadyApplied($context)) {
            $this.WriteInfo("既に適用済みです。スキップします。")
            return $this.CreateSuccessResult("既に適用済みです")
        }

        # 処理を実行
        $this.WriteInfo("処理を開始します")
        # ...

        return $this.CreateSuccessResult("成功")
    } catch {
        return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
    }
}

hidden [bool] IsAlreadyApplied([SetupContext]$context) {
    # チェックロジック
    # 例: ファイルが既に存在する、設定が既に適用されているなど
    $configFile = Join-Path $context.RootPath ".applied"
    return (Invoke-TestPath $configFile)
}
```

### 冪等性のチェックポイント

- [ ] ファイルが既に存在する場合、上書きするか？スキップするか？
- [ ] 設定が既に適用されている場合、再適用するか？スキップするか？
- [ ] 処理が途中で失敗した場合、再実行時に継続できるか？

### 例: ファイルコピーの冪等性

```powershell
# ✅ 冪等（既存チェック）
if (-not (Invoke-TestPath $destination)) {
    Invoke-CopyItem -Source $source -Destination $destination
}

# ⚠️ 非冪等（毎回上書き）
Invoke-CopyItem -Source $source -Destination $destination -Force
```

## 2. テスタビリティ（Testability）

### 定義

すべての外部依存をモック可能にし、ユニットテストで容易に検証できるようにします。

### ラッパー関数の使用

```powershell
# ✅ テスト可能
[SetupResult] Apply([SetupContext]$context) {
    try {
        $output = Invoke-Wsl -ArgumentList "--version"
        return $this.CreateSuccessResult("WSL version: $output")
    } catch {
        return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
    }
}

# テストでモック
Mock Invoke-Wsl { return "WSL version: 2.0.0" }

# ❌ テスト不可
[SetupResult] Apply([SetupContext]$context) {
    try {
        $output = wsl.exe --version
        return $this.CreateSuccessResult("WSL version: $output")
    } catch {
        return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
    }
}
```

### モック可能な依存の種類

1. **外部コマンド**: `Invoke-Wsl`, `Invoke-Chezmoi`, `Invoke-Diskpart`
2. **ファイル操作**: `Invoke-TestPath`, `Invoke-GetContent`, `Invoke-SetContent`
3. **プロセス起動**: `Invoke-StartProcess`

### テストの構造

```powershell
Describe 'YourHandler' {
    Context 'CanApply' {
        It '条件を満たす場合は true を返す' {
            Mock Invoke-TestPath { return $true }

            $handler = [YourHandler]::new()
            $context = [SetupContext]::new("C:\test")

            $result = $handler.CanApply($context)
            $result | Should -Be $true
        }
    }

    Context 'Apply' {
        It '成功時は Success = $true を返す' {
            Mock Invoke-SomeCommand { return "success" }

            $handler = [YourHandler]::new()
            $context = [SetupContext]::new("C:\test")

            $result = $handler.Apply($context)

            $result.Success | Should -Be $true
            Should -Invoke Invoke-SomeCommand -Times 1 -Exactly
        }

        It 'エラー時は Success = $false を返す' {
            Mock Invoke-SomeCommand { throw "error" }

            $handler = [YourHandler]::new()
            $context = [SetupContext]::new("C:\test")

            $result = $handler.Apply($context)

            $result.Success | Should -Be $false
            $result.Error | Should -Not -BeNullOrEmpty
        }
    }
}
```

## 3. エラーリカバリー（Error Recovery）

### 定義

エラー時も適切な結果を返し、システムを不安定な状態にしません。例外を適切にキャッチし、ログを出力します。

### エラーハンドリングパターン

```powershell
[SetupResult] Apply([SetupContext]$context) {
    try {
        $this.WriteInfo("処理を開始します")

        # ステップ 1
        $result1 = $this.ExecuteStep1($context)

        # ステップ 2
        $result2 = $this.ExecuteStep2($context, $result1)

        $this.WriteSuccess("すべてのステップが完了しました")
        return $this.CreateSuccessResult("成功")

    } catch {
        # 詳細なエラーログ
        $this.WriteError("エラーが発生しました: $($_.Exception.Message)")
        $this.WriteError("スタックトレース: $($_.ScriptStackTrace)")

        # 失敗結果を返す（例外を再スローしない）
        return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
    }
}
```

### ロールバック処理

```powershell
[SetupResult] Apply([SetupContext]$context) {
    $backupPath = $null

    try {
        # バックアップ作成
        $backupPath = $this.CreateBackup($context)

        # メイン処理
        $this.ExecuteMainProcess($context)

        # バックアップ削除
        $this.RemoveBackup($backupPath)

        return $this.CreateSuccessResult("成功")

    } catch {
        $this.WriteError("エラーが発生しました: $($_.Exception.Message)")

        # ロールバック
        if ($backupPath -and (Invoke-TestPath $backupPath)) {
            $this.WriteInfo("ロールバックを実行します")
            $this.RestoreBackup($backupPath)
        }

        return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
    }
}
```

### エラーメッセージのベストプラクティス

```powershell
# ✅ 詳細（何が、どこで、なぜ失敗したか）
$this.WriteError("VHD 拡張に失敗しました: ファイル '$vhdPath' が見つかりません")

# ❌ 不明瞭
$this.WriteError("エラーが発生しました")
```

## 4. ハンドラー間の依存（Handler Dependencies）

### 定義

ハンドラーは Order プロパティで実行順序を制御し、SharedData でデータを共有します。

### Order プロパティの設定

```powershell
class WslConfigHandler : SetupHandlerBase {
    WslConfigHandler() {
        $this.Order = 10  # 最初に実行
    }
}

class DockerHandler : SetupHandlerBase {
    DockerHandler() {
        $this.Order = 20  # WslConfig の後に実行
    }
}

class ChezmoiHandler : SetupHandlerBase {
    ChezmoiHandler() {
        $this.Order = 100  # 最後に実行
    }
}
```

**推奨**: Order は 10 刻みで設定し、将来の挿入を容易にします。

### SharedData によるデータ共有

```powershell
# ハンドラー A（Order 10）
[SetupResult] Apply([SetupContext]$context) {
    $vhdPath = "C:\path\to.vhdx"
    $context.SharedData["WslConfig_VhdPath"] = $vhdPath

    $this.WriteInfo("VHD パスを SharedData に保存しました: $vhdPath")
    return $this.CreateSuccessResult("成功")
}

# ハンドラー B（Order 20）
[SetupResult] Apply([SetupContext]$context) {
    # SharedData から VHD パスを取得
    $vhdPath = $context.SharedData["WslConfig_VhdPath"]

    if ($vhdPath) {
        $this.WriteInfo("VHD パスを SharedData から取得しました: $vhdPath")
        # VHD パスを使用した処理
    } else {
        $this.WriteInfo("VHD パスが SharedData にありません。スキップします。")
    }

    return $this.CreateSuccessResult("成功")
}
```

**命名規則**: SharedData のキーは `{HandlerName}_{PropertyName}` 形式を推奨

### 依存関係の明示

```powershell
[bool] CanApply([SetupContext]$context) {
    # 前提条件: WslConfigHandler が実行済み
    if (-not $context.SharedData.ContainsKey("WslConfig_VhdPath")) {
        $this.WriteInfo("WslConfigHandler が未実行のため、スキップします")
        return $false
    }

    return $true
}
```

## 5. ログ出力の一貫性（Consistent Logging）

### ログレベル

- **WriteInfo**: 処理の開始、中間状態、情報メッセージ（青）
- **WriteSuccess**: 処理の成功、完了メッセージ（緑）
- **WriteError**: エラー、失敗メッセージ（赤）

### ログ出力の例

```powershell
[SetupResult] Apply([SetupContext]$context) {
    try {
        $this.WriteInfo("Docker Desktop WSL 連携を開始します")

        # ステップ 1
        $this.WriteInfo("docker-desktop distro を作成します")
        $this.CreateDockerDesktopDistro()
        $this.WriteSuccess("docker-desktop distro を作成しました")

        # ステップ 2
        $this.WriteInfo("docker グループにユーザーを追加します")
        $this.AddUserToDockerGroup()
        $this.WriteSuccess("docker グループにユーザーを追加しました")

        $this.WriteSuccess("Docker Desktop WSL 連携が完了しました")
        return $this.CreateSuccessResult("成功")

    } catch {
        $this.WriteError("Docker Desktop WSL 連携に失敗しました: $($_.Exception.Message)")
        return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
    }
}
```

### ユーザー向けメッセージ

```powershell
# ✅ 詳細で理解しやすい
$this.WriteInfo("VHD を 256GB に拡張しています（数分かかる場合があります）")

# ❌ 不明瞭
$this.WriteInfo("処理中...")
```

## 6. セキュリティ（Security）

### パスワード・シークレットの扱い

```powershell
# ✅ 環境変数から取得
$apiKey = $env:API_KEY
if (-not $apiKey) {
    throw "API_KEY 環境変数が設定されていません"
}

# ❌ ハードコード
$apiKey = "secret123"
```

### ファイルパスの検証

```powershell
# ✅ パストラバーサル対策
$normalizedPath = [System.IO.Path]::GetFullPath($userInputPath)
if (-not $normalizedPath.StartsWith($context.RootPath)) {
    throw "不正なパスです: $userInputPath"
}

# ❌ 検証なし
$path = Join-Path $context.RootPath $userInputPath
```

### コマンドインジェクション対策

```powershell
# ✅ 配列でパラメータ渡し
$output = Invoke-Wsl -ArgumentList "--list", "--verbose"

# ⚠️ 文字列結合（インジェクションリスク）
$command = "wsl.exe --list $userInput"
& $command
```

## まとめ

### チェックリスト

新しいハンドラーを実装する際は、以下の原則を守ってください:

- [ ] **冪等性**: 何度実行しても同じ結果になるか？
- [ ] **テスタビリティ**: すべての外部依存がモック可能か？
- [ ] **エラーリカバリー**: エラー時も適切な結果を返すか？
- [ ] **ハンドラー間依存**: Order と SharedData を適切に使用しているか？
- [ ] **ログ出力**: ユーザーに分かりやすいメッセージを出力しているか？
- [ ] **セキュリティ**: パスワード、パス、コマンドを安全に扱っているか？
