# Handler Tests

Purpose: ハンドラーのユニットテスト

## ファイル一覧

| ファイル | 対象 |
|----------|------|
| `Handler.WslConfig.Tests.ps1` | WslConfigHandler |
| `Handler.Docker.Tests.ps1` | DockerHandler |
| `Handler.VscodeServer.Tests.ps1` | VscodeServerHandler |
| `Handler.Chezmoi.Tests.ps1` | ChezmoiHandler |

## テスト構造

各テストファイルは以下の Context で構成：

1. **コンストラクタ**: Name, Description, Order, RequiresAdmin の確認
2. **CanApply**: 各条件での適用可否チェック
3. **Apply - 正常系**: 成功パスのテスト
4. **Apply - 失敗系**: エラーパスのテスト
5. **個別メソッド**: hidden メソッドのテスト

## BeforeAll / BeforeEach

```powershell
BeforeAll {
    # ソースファイル読み込み
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.MyHandler.ps1
}

BeforeEach {
    # ハンドラーとコンテキストを初期化
    $script:handler = [MyHandler]::new()
    $script:ctx = [SetupContext]::new("D:\dotfiles")
}
```

## モック戦略

### 変数トラッキングパターン

`Should -Invoke` はパイプライン入力を受け付けないため、変数でトラッキング：

```powershell
It 'WSL コマンドが呼ばれる' {
    $script:wslCalled = $false
    Mock Invoke-Wsl { $script:wslCalled = $true }

    $handler.Apply($ctx)

    $script:wslCalled | Should -Be $true
}
```

### 引数による分岐

```powershell
Mock Invoke-Wsl {
    param($Arguments)
    $argStr = $Arguments -join " "
    if ($argStr -match "whoami") {
        $global:LASTEXITCODE = 0
        return "testuser"
    }
    if ($argStr -match "df -Pk") {
        return "50000"
    }
    return ""
}
```
