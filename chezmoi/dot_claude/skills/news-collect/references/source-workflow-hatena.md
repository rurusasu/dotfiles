# Hatena Bookmark Source Workflow

はてなブックマーク（IT人気エントリー）経由で記事を取得し、Markdown に保存する手順。

## Steps

1. `web_fetch: https://b.hatena.ne.jp/hotentry/it.rss` で RSS を取得する。
2. 上位5〜10件の `title/link/hatena:bookmarkcount` を抽出する。
3. 各 `link`（外部記事）に `web_fetch` を実行して本文取得を試みる。
4. 成功時は `hatena/{index}_{sanitized_title}.md` に保存する。
5. 失敗時は保存せず、`report.md` の該当行に `本文取得失敗` と理由を記録する。

## Notes

- 外部サイト側の制約（robots / paywall / 403）により取得不可の場合がある。
- RSS が扱いにくい形式で返る場合は代替ソースを使う（既存 SKILL.md の troubleshooting に従う）。

## File Template

```markdown
---
title: "記事タイトル"
source: HatenaBookmark
url: https://external-article-url
author: 著者名
date: YYYY-MM-DD
fetched_at: YYYY-MM-DD HH:MM JST
score: ブックマーク数
---

本文（取得できたテキスト）
```
