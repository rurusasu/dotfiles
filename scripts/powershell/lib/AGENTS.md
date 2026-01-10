# Lib

Purpose: 共通ライブラリ

## ファイル一覧

| ファイル | 説明 |
|----------|------|
| `SetupHandler.ps1` | 基底クラスとコンテキスト定義 |
| `Invoke-ExternalCommand.ps1` | 外部コマンドラッパー関数群 |

## SetupHandler.ps1

### クラス定義

- **`SetupContext`**: セットアップコンテキスト（パス、オプション等）
- **`SetupResult`**: 処理結果（成功/失敗、メッセージ、例外）
- **`SetupHandlerBase`**: ハンドラー基底クラス

### SetupContext プロパティ

```powershell
$ctx = [SetupContext]::new("D:\dotfiles")
$ctx.DotfilesPath   # dotfiles ルートパス
$ctx.DistroName     # WSL ディストリビューション名（デフォルト: NixOS）
$ctx.InstallDir     # インストール先ディレクトリ
$ctx.Options        # オプション hashtable
```

### SetupHandlerBase メソッド

- `CanApply($ctx)`: 適用可能かチェック（オーバーライド必須）
- `Apply($ctx)`: 処理実行（オーバーライド必須）
- `Log($message, $color)`: ログ出力
- `LogWarning($message)`: 警告出力（黄色）
- `LogError($message)`: エラー出力（赤色）
- `CreateSuccessResult($message)`: 成功結果生成
- `CreateFailureResult($message, $exception)`: 失敗結果生成

## Invoke-ExternalCommand.ps1

外部コマンドをラップしてテストでモック可能にする関数群。

### 主要関数

| 関数 | 説明 |
|------|------|
| `Invoke-Wsl` | WSL コマンド実行 |
| `Invoke-Chezmoi` | chezmoi コマンド実行 |
| `Invoke-Diskpart` | diskpart コマンド実行 |
| `Get-ExternalCommand` | コマンド存在確認 |
| `Test-PathExists` | パス存在確認 |
| `Get-ProcessSafe` | プロセス取得 |
| `Stop-ProcessSafe` | プロセス停止 |
| `Start-ProcessSafe` | プロセス起動 |
| `Copy-FileSafe` | ファイルコピー |
| `Get-FileContentSafe` | ファイル読み取り |
| `Get-JsonContent` | JSON ファイル読み取り |
| `New-DirectorySafe` | ディレクトリ作成 |
| `Get-ChildItemSafe` | ディレクトリ内容取得 |
| `Get-RegistryValue` | レジストリ値取得 |
| `Get-RegistryChildItem` | レジストリ子キー取得 |

### テストでのモック例

```powershell
Mock Invoke-Wsl {
    param($Arguments)
    if (($Arguments -join " ") -match "whoami") {
        $global:LASTEXITCODE = 0
        return "testuser"
    }
    return ""
}
```
