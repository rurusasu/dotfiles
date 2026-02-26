# Zenn Source Workflow

Zenn から記事を取得して Markdown ファイル保存まで行う手順。

## Steps

1. `web_fetch: https://zenn.dev/feed` で RSS を取得する。
2. 上位5〜10件の `title/link/pubDate/dc:creator` を抽出する。
3. 各 `link` に `web_fetch` を実行して本文テキストを取得する。
4. `zenn/{index}_{slug}.md` に保存する。
5. `report.md` の Zenn セクションへ、タイトル・URL・著者・公開日・保存先相対パスを追記する。

## Notes

- 公開記事のみ対象。有料コンテンツは除外する。
- `text_content_token_limit` は必要十分な値（目安 4000〜8000）を使う。
- 取得失敗時はスキップし、`report.md` に理由を記録する。

## File Template

```markdown
---
title: "記事タイトル"
source: Zenn
url: https://zenn.dev/{user}/articles/{slug}
author: 著者名
date: YYYY-MM-DD
fetched_at: YYYY-MM-DD HH:MM JST
---

本文（取得できたテキスト）
```
