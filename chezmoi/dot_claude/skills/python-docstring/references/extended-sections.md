# Extended Sections Guide

Google スタイルに加え、コードの意図と背景を残すための拡張セクション。

## Design Decisions

なぜこの実装を選んだかを記述。トレードオフや代替案の検討結果を含める。

```python
"""データベース接続プールを管理する.

Design Decisions:
    1. **接続プールサイズの選択**:
       同時リクエスト数の実測値（平均50、ピーク100）に基づき、
       pool_size=20, max_overflow=30 を採用。
       過大なプールはメモリを浪費し、過小はレイテンシ増加を招く。

    2. **コネクション取得タイムアウト**:
       pool_timeout=10秒に設定。これ以上待機する場合は
       リトライより早期失敗が望ましいと判断。

    3. **SQLAlchemy vs 生 psycopg2**:
       ORMの抽象化コストより、保守性とテスタビリティを優先。
"""
```

## Change Rationale

リファクタリングや仕様変更の理由を記述。

```python
"""ユーザー認証を処理する.

Change Rationale:
    2024-01-15: セッション管理を Redis から JWT に変更。
    - 水平スケーリング時のセッション共有問題を解消
    - 参照: Issue #234, PR #256

    2024-03-01: トークン有効期限を 24h から 1h に短縮。
    - セキュリティ監査での指摘に対応
    - リフレッシュトークン機構を追加
"""
```

## References

実装の根拠となる外部ドキュメント、Issue、PR へのリンク。

```python
"""非同期バッチ処理を実行する.

References:
    - Python asyncio ドキュメント: https://docs.python.org/3/library/asyncio.html
    - 設計レビュー: https://github.com/org/repo/issues/123
    - 関連 PR: https://github.com/org/repo/pull/456
    - 参考実装: https://github.com/example/lib/blob/main/batch.py
"""
```

## Background

機能やクラスが存在する理由、ビジネス要件との関連を記述。

```python
"""レート制限を適用するデコレータ.

Background:
    2023年Q3の負荷テストで、無制限APIアクセスによる
    データベース過負荷が発覚。SLA（99.9%可用性）達成のため、
    エンドポイントごとのレート制限を導入。

    要件:
    - 無料プラン: 100 req/min
    - 有料プラン: 1000 req/min
    - エンタープライズ: 無制限（別途契約）
"""
```

## Constraints

技術的・ビジネス的な制約事項を記述。

```python
"""外部APIクライアント.

Constraints:
    - API レート制限: 1000 req/day（2024-01時点）
    - 最大ペイロード: 10MB
    - サポート対象: API v2 のみ（v1 は 2024-06 に廃止予定）
    - タイムアウト: サーバー側で 30秒に固定（変更不可）
"""
```

## Section Order (Recommended)

1. 一行サマリー
2. 詳細説明
3. Design Decisions / Background / Change Rationale（状況に応じて）
4. Constraints（あれば）
5. Args / Attributes
6. Returns / Yields
7. Raises
8. Example(s)
9. Note(s) / Warning(s)
10. References
11. See Also / Todo

## Writing Tips

- **具体的な数値**: 「大量」→「10万件以上」
- **日付を残す**: 変更理由には日付を付与
- **リンクは生きているものを**: 定期的にリンク切れを確認
- **Why を重視**: What（何をするか）より Why（なぜそうするか）を詳しく
