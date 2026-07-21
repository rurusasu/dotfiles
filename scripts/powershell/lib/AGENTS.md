# lib: 共通ライブラリ編集ガイド

## 対象ファイル

- `SetupHandler.ps1`: `SetupContext`, `SetupResult`, `SetupHandlerBase`
- `Invoke-ExternalCommand.ps1`: モック可能な `Invoke-*` ラッパー群
- `HermesBootstrap.ps1`: 1Password item JSON を bootstrap container へ stdin で転送する transport

## 変更ルール

- ハンドラーから呼ぶ OS/外部コマンドはラッパー関数として追加する。
- 既存関数のインターフェースを変える場合は利用ハンドラーとテストを同時更新する。
- 直接コマンド呼び出しを増やさない。
- `HermesBootstrap.ps1` は transport のみを所有する。secret の解釈、永続化、`.env` や profile の更新は container 側が所有する。
- payload の stdin stream は `HermesBootstrap.ps1` の redirected `ProcessStartInfo` だけで扱う。通常の外部コマンド wrapper へ戻したり payload をファイル化したりしない。1Password lookup は injectable invoker として保つ。

## テスト

```powershell
cd scripts/powershell/tests
.\Invoke-Tests.ps1 -Path .\lib\SetupHandler.Tests.ps1 -MinimumCoverage 0
.\Invoke-Tests.ps1 -Path .\lib\Invoke-ExternalCommand.Tests.ps1 -MinimumCoverage 0
```
