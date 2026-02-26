# X Twitter Source Workflow

X (Twitter) は規約順守のため `web_search` のみを使用し、要約ファイルとして保存する手順。

## Steps

1. `web_search` でトレンド関連クエリを実行する。
2. 結果からトピック、参照 URL、要点を抽出する。
3. `x_twitter/summary.md` に保存する。
4. `report.md` に `summary.md` への相対リンクを記載する。

## Query Examples

- `"X Twitter tech AI trending today"`
- `"Twitter テック トレンド 話題 今日"`

## Notes

- X 本体の自動スクレイピングはしない。
- 本文記事の保存は行わず、検索結果の要約のみ保存する。

## Summary Template

```markdown
---
source: X
date: YYYY-MM-DD
fetched_at: YYYY-MM-DD HH:MM JST
method: web_search
---

## Topics

1. トピック名 - 根拠URL
2. トピック名 - 根拠URL

## Notes

- リアルタイム性は検索インデックス依存。
```
