# lib: 共通ライブラリ編集ガイド

## 対象ファイル

- `SetupHandler.ps1`: `SetupContext`, `SetupResult`, `SetupHandlerBase`
- `Invoke-ExternalCommand.ps1`: モック可能な `Invoke-*` ラッパー群

## 変更ルール

- ハンドラーから呼ぶ OS/外部コマンドはラッパー関数として追加する。
- 既存関数のインターフェースを変える場合は利用ハンドラーとテストを同時更新する。
- 直接コマンド呼び出しを増やさない。

## テスト

```powershell
cd scripts/powershell/tests
.\Invoke-Tests.ps1 -Path .\lib\SetupHandler.Tests.ps1 -MinimumCoverage 0
.\Invoke-Tests.ps1 -Path .\lib\Invoke-ExternalCommand.Tests.ps1 -MinimumCoverage 0
```
