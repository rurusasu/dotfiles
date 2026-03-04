# PowerShell: 実装ルールと検証手順

## 実装で必ず守るルール

1. ハンドラーは `Handler.<Name>.ps1` / `<Name>Handler : SetupHandlerBase` を守る。
2. 外部コマンドは直接呼ばず `Invoke-*` ラッパー経由にする。
3. `Apply()` は例外を投げず `SetupResult` を返す。
4. テストは `tests/Invoke-Tests.ps1` 経由で実行する。
5. Pester の `It` 名は `should ...` 形式で書く。

## 編集対象

- `lib/SetupHandler.ps1`: 基底クラス・共通型
- `lib/Invoke-ExternalCommand.ps1`: 外部コマンドラッパー
- `handlers/Handler.*.ps1`: セットアップ処理
- `tests/**/*.Tests.ps1`: ユニットテスト

## テストコマンド

```powershell
cd scripts/powershell/tests
.\Invoke-Tests.ps1
.\Invoke-Tests.ps1 -All -IncludeBats
.\Invoke-Tests.ps1 -MinimumCoverage 0
```

```powershell
task test:powershell
```

## ドキュメント更新条件

以下を変更したら `docs/scripts/powershell/` も更新する。

- ハンドラー実行順序
- ラッパー関数の追加/削除
- テスト方針と命名規則
