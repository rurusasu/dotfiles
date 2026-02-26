# Handler Tests

Purpose: `handlers/Handler.*.ps1` のユニットテスト方針

## 対応ルール

- `Handler.X.ps1` ごとに `Handler.X.Tests.ps1` を作成する
- コンストラクタ / `CanApply` / `Apply` を最低限カバーする
- `RequiresAdmin` の分岐は明示的にテストする

## 推奨構造

1. `Context 'Constructor'`
2. `Context 'CanApply'`
3. `Context 'Apply - success'`
4. `Context 'Apply - failure'`

## モック戦略

- 外部コマンドは `Invoke-*` ラッパーのみ `Mock` する
- 呼び出し確認は変数トラッキング方式を優先する
- 引数分岐がある場合は `param($Arguments)` で判定して返り値を切り替える
