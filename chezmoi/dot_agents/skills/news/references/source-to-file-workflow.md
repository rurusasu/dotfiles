# Source To File Workflow Index

情報源ごとの取得から保存までの詳細手順は、以下の分割ファイルを参照する。

## Source Files

- Zenn: `references/source-workflow-zenn.md`
- Hatena Bookmark: `references/source-workflow-hatena.md`
- Hacker News: `references/source-workflow-hackernews.md`
- X (Twitter): `references/source-workflow-x-twitter.md`

## Common Rules

- 記事本文は必要時のみ取得する。
- 記事本文取得は `web_fetch` を使う。
- 取得件数は合計15〜20件以内に抑える。
- 保存先は `/mnt/user-data/outputs/tech-news-YYYY-MM-DD/` を使う。
- 失敗したURL（403 / robots / paywall）はスキップし、`report.md` に失敗理由を記録する。
- X は Grok API `x_search` で投稿内容を取得する。APIキー不可時は web_search フォールバック。

## Directory Layout

```text
tech-news-YYYY-MM-DD/
├── report.md
├── zenn/
├── hatena/
├── hackernews/
└── x_twitter/
```

## Report Requirements

`report.md` には以下を必ず含める。

- 収集日時（JST）
- ソースごとの一覧テーブル
- 各記事の元URL
- 保存済み記事ファイルへの相対リンク
- 取得失敗ログ（理由付き）
