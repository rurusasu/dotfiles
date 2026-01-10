# Lib Tests

Purpose: 共通ライブラリのユニットテスト

## ファイル一覧

| ファイル | 対象 |
|----------|------|
| `SetupHandler.Tests.ps1` | SetupContext, SetupResult, SetupHandlerBase |
| `Invoke-ExternalCommand.Tests.ps1` | 外部コマンドラッパー関数群 |

## SetupHandler.Tests.ps1

### テスト対象

- **SetupContext**: コンストラクタ、GetOption、プロパティ設定
- **SetupResult**: コンストラクタ、CreateSuccess、CreateFailure
- **SetupHandlerBase**: プロパティ、CanApply/Apply（例外スロー確認）、Log メソッド群

## Invoke-ExternalCommand.Tests.ps1

### テスト対象

すべてのラッパー関数をテスト：

- `Invoke-Wsl`
- `Invoke-Diskpart`
- `Get-ExternalCommand`
- `Test-PathExists`
- `Get-ProcessSafe`
- `Stop-ProcessSafe`
- `Start-ProcessSafe`
- `Copy-FileSafe`
- `Get-FileContentSafe`
- `Get-JsonContent`
- `New-DirectorySafe`
- `Get-ChildItemSafe`
- `Get-RegistryValue`
- `Get-RegistryChildItem`
- `Invoke-WebRequestSafe`
- `Invoke-RestMethodSafe`
- `Start-SleepSafe`

### カバー不可能なコード

以下は外部コマンド/ファイルシステム操作のため、ユニットテストでカバー不可：

| 関数 | 行 | コード |
|------|-----|--------|
| `Invoke-Chezmoi` | 53 | `if ($ExePath)` |
| `Invoke-Chezmoi` | 54 | `& $ExePath @Arguments` |
| `Invoke-Chezmoi` | 56 | `& chezmoi @Arguments` |
| `Set-ContentNoNewline` | 101 | `Set-Content ... -NoNewline` |

これらは**統合テスト**でカバーする必要があります。
