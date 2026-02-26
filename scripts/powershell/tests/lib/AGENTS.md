# Lib Tests

Purpose: `scripts/powershell/lib` の共通ライブラリテスト方針

## 対象ファイル

- `SetupHandler.Tests.ps1`: `SetupContext` / `SetupResult` / `SetupHandlerBase`
- `Invoke-ExternalCommand.Tests.ps1`: `Invoke-*` ラッパー群
- `Request-AdminElevation.Tests.ps1`: 管理者権限判定と昇格要求フロー

## ガイドライン

1. ライブラリ API の戻り値と例外経路を両方検証する
2. 実コマンド実行は避け、`Mock` で副作用を隔離する
3. カバレッジ対象外の行は理由をコメントで残す
