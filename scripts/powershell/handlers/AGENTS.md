# handlers: ハンドラー実装ルール

## 実装要件

1. `SetupHandlerBase` 継承クラスにする。
2. `Name`, `Description`, `Order`, `RequiresAdmin` をコンストラクタで設定する。
3. `CanApply()` で適用可否を返す。
4. `Apply()` は `CreateSuccessResult` / `CreateFailureResult` を返す。
5. 外部コマンドは `Invoke-*` ラッパーを使う。

## 追加時の手順

1. `Handler.<Name>.ps1` を作成する。
2. `tests/handlers/Handler.<Name>.Tests.ps1` を作成する。
3. 依存順に `Order` を決める。
4. `tests/Invoke-Tests.ps1` で確認する。
