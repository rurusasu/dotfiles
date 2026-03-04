# tests/lib: ライブラリテスト方針

## 対象

- `SetupHandler.Tests.ps1`
- `Invoke-ExternalCommand.Tests.ps1`
- `Request-AdminElevation.Tests.ps1`

## 重点確認

1. `SetupContext` / `SetupResult` / `SetupHandlerBase` の契約を壊していないこと。
2. ラッパー関数の引数処理と例外処理が維持されること。
3. 実コマンド実行が必要な部分は統合テストで補うこと。
