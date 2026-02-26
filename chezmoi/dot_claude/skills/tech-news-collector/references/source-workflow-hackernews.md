# Hacker News Source Workflow

Hacker News 公式 API から記事を取得し、Markdown に保存する手順。

## Steps

1. `web_fetch: https://hacker-news.firebaseio.com/v0/topstories.json` で ID 配列を取得する。
2. 先頭5〜10件の ID について `web_fetch: https://hacker-news.firebaseio.com/v0/item/{id}.json` を実行する。
3. `title/url/score/by/descendants` を抽出する。
4. `url` がある記事は `web_fetch` で本文取得を試みる。
5. 成功時は `hackernews/{index}_{sanitized_title}.md` に保存する。
6. `url` なし（Ask HN など）または取得失敗時は本文ファイルを作らず、`report.md` に状態を記録する。

## Notes

- API は1記事ごとに個別リクエストが必要。
- 外部リンク先が取得不可の場合はメタ情報のみ保存対象にする。

## File Template

```markdown
---
title: "記事タイトル"
source: HackerNews
url: https://external-article-url
author: 投稿者名
date: YYYY-MM-DD
fetched_at: YYYY-MM-DD HH:MM JST
score: upvote数
comments: コメント数
---

本文（取得できたテキスト）
```
