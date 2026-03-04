# tests/handlers: ハンドラーテスト方針

## テスト構成

- `コンストラクタ`: メタ情報 (`Name`, `Order` など)
- `CanApply`: 適用条件
- `Apply`: 成功系/失敗系
- 必要な private 相当メソッドの挙動

## 記述ルール

- `BeforeAll` で対象ハンドラーをロードする。
- `BeforeEach` で `handler` と `SetupContext` を初期化する。
- 外部依存は `Mock Invoke-*` で置き換える。
