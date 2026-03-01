---
name: tech-news-collector
description: |
  テック系ニュースの人気記事を複数の情報源から一括収集するスキル。
  対応ソース: Zenn（トレンド）、はてなブックマーク（IT人気エントリー）、Hacker News（トップストーリー）、X/Twitter（テックトレンド）。
  「テックニュースを集めて」「今日の人気記事を教えて」「技術トレンドをまとめて」
  「Zenn/はてブ/HN/Xのトレンドは？」「IT系の最新記事を収集して」
  「tech news」「trending articles」などのリクエストで必ずこのスキルを使うこと。
  web_search / web_fetch / Claude in Chrome のいずれかを情報源に応じて使い分ける。
---

# Tech News Collector

テック系の人気記事を4つの情報源から収集し、統合レポートとして提示するスキル。

詳細な「情報源ごとの取得→本文取得→ファイル保存」手順は `references/source-to-file-workflow.md` を参照すること。

## 利用規約コンプライアンス（最重要）

**このスキルは各サービスの利用規約を厳守する。絶対に違反しないこと。**

| 情報源             | 取得方法            | 根拠                                                                                      |
| ------------------ | ------------------- | ----------------------------------------------------------------------------------------- |
| Zenn               | 公式RSSフィード     | Zenn公式ドキュメント `zenn.dev/zenn/articles/zenn-feed-rss` で提供                        |
| はてなブックマーク | 公式RSSフィード     | はてな公式提供。カテゴリURL末尾に `.rss` 付加で取得可能                                   |
| Hacker News        | 公式Firebase API    | `github.com/HackerNews/API` で公開。認証不要・無料                                        |
| X (Twitter)        | web_search **のみ** | X利用規約でスクレイピング・自動データ収集を明確に禁止。検索エンジン経由の公開情報参照のみ |

**禁止事項:**

- X (Twitter) のページを直接スクレイピングすること
- 各サービスへの過度なリクエスト（短時間での大量アクセス）
- 記事本文の全文取得・複製（タイトル・URL・メタデータのみ取得すること）

## 収集手順

### 1. Zenn トレンド記事

`web_fetch` で公式RSSフィードを取得する。

```
web_fetch: https://zenn.dev/feed
```

XMLレスポンスから各 `<item>` 要素を解析し、以下を抽出:

- `<title>`: 記事タイトル
- `<link>`: 記事URL
- `<pubDate>`: 公開日時
- `<dc:creator>`: 著者名

上位5〜10件を取得する。

### 2. はてなブックマーク IT人気エントリー

`web_fetch` で公式RSSフィードを取得する。

```
web_fetch: https://b.hatena.ne.jp/hotentry/it.rss
```

RSS 1.0 (RDF) 形式。各 `<item>` から以下を抽出:

- `<title>`: 記事タイトル
- `<link>`: 記事URL
- `<hatena:bookmarkcount>`: ブックマーク数

上位5〜10件を取得する。

### 3. Hacker News トップストーリー

公式Firebase APIを使用して2段階で取得する。

**Step 1**: トップストーリーのID一覧を取得

```
web_fetch: https://hacker-news.firebaseio.com/v0/topstories.json
```

レスポンスはIDの配列。先頭10件のIDを使用する。

**Step 2**: 各IDの詳細を個別取得

```
web_fetch: https://hacker-news.firebaseio.com/v0/item/{id}.json
```

各アイテムのJSONから以下を抽出:

- `title`: タイトル
- `url`: 外部リンクURL
- `score`: スコア（upvote数）
- `by`: 投稿者名
- `descendants`: コメント数

**注意**: 1記事ごとに1リクエスト必要。取得件数は5〜10件に抑えること。

### 4. X (Twitter) テックトレンド

**X (Twitter) は利用規約でスクレイピング・自動データ収集を明確に禁止している。**

以下の方法のみ使用する:

#### 方法A（デフォルト）: web_search を使用

```
web_search: "X Twitter tech AI trending today 2026"
web_search: "Twitter テック トレンド 話題 今日"
```

#### 方法B: Claude in Chrome を使用

ユーザーが明示的に指示した場合のみ、ユーザーのブラウザで通常のブラウジングとして閲覧。

- これは手動ブラウジングの代行であり、自動スクレイピングではない
- 大量データ収集は行わない。表示されている内容を読み取る程度にとどめる

web_search経由の場合、リアルタイム性が低い点をユーザーに説明すること。

## 記事本文のダウンロード

RSSやAPIで取得したメタデータ（タイトル・URL）に加え、各記事の本文を `web_fetch` で取得する。

### ダウンロードフロー

RSSフィード/API/web_search でメタ情報を収集した後、以下のフローで記事本文を取得する。

#### Step A: 記事URLに `web_fetch` を実行

```
web_fetch: {記事URL}  (text_content_token_limit を適切に設定)
```

- Zenn記事 → `web_fetch: https://zenn.dev/{user}/articles/{slug}` で本文取得可能（動作確認済み）
- HN経由の外部記事 → `web_fetch: {item.url}` で外部サイトの記事を取得
- はてブ経由の外部記事 → `web_fetch: {item.link}` で外部サイトの記事を取得

#### Step B: 取得したテキストをマークダウンファイルとして保存

```
各記事を以下のフォーマットで /mnt/user-data/outputs/ に保存:

tech-news-YYYY-MM-DD/
├── report.md              # 統合レポート（一覧+サマリ）
├── zenn/
│   ├── 01_記事slug.md
│   └── 02_記事slug.md
├── hatena/
│   ├── 01_記事タイトル.md
│   └── 02_記事タイトル.md
├── hackernews/
│   ├── 01_記事タイトル.md
│   └── 02_記事タイトル.md
└── x_twitter/
    └── (web_search結果のサマリ.md)
```

#### Step C: 各記事ファイルのヘッダーにメタ情報を付与

```markdown
---
title: "記事タイトル"
source: Zenn / HatenaBookmark / HackerNews / X
url: https://original-article-url
author: 著者名（取得できた場合）
date: YYYY-MM-DD
fetched_at: YYYY-MM-DD HH:MM JST
score: スコア/ブックマーク数（取得できた場合）
---

（ここから記事本文テキスト）
```

### 利用規約に基づく制約

- Zenn
  - 記事本文取得: ✅ 可能
  - 方法: `web_fetch` で個別記事ページを取得
  - 注意事項: 公開記事のみ。有料コンテンツは不可。サーバー負荷に配慮し間隔を空ける
- はてブ経由の外部記事
  - 記事本文取得: ⚠️ サイトによる
  - 方法: `web_fetch` で外部サイトを取得
  - 注意事項: robots.txtでブロックされる場合あり。取得失敗時はスキップ
- HN経由の外部記事
  - 記事本文取得: ⚠️ サイトによる
  - 方法: `web_fetch` で外部サイトを取得
  - 注意事項: 同上。ペイウォール記事は取得不可
- X (Twitter)
  - 記事本文取得: ❌ 不可
  - 方法: web_search結果のサマリのみ
  - 注意事項: X利用規約で自動データ収集禁止。検索結果の要約のみ保存

### サーバー負荷への配慮

- 短時間に大量のリクエストを送らないこと
- 1回の収集で取得する記事数は合計15〜20件程度を上限とする
- `web_fetch` の `text_content_token_limit` を 4000〜8000 に設定し、必要以上のデータを取得しない
- 取得失敗（403, robots.txt拒否等）はログに記録し、エラー記事はスキップする

## 出力フォーマット

### A. 会話内表示（デフォルト）

```markdown
## 📰 テックニュース収集レポート

**収集日時**: YYYY-MM-DD HH:MM (JST)

---

### 🔥 Zenn トレンド

| #   | タイトル        | 著者   | 公開日     |
| --- | --------------- | ------ | ---------- |
| 1   | [タイトル](URL) | 著者名 | YYYY-MM-DD |

### 📌 はてなブックマーク IT人気エントリー

| #   | タイトル        | ブックマーク数 |
| --- | --------------- | -------------- |
| 1   | [タイトル](URL) | 🔖 XXX users   |

### 🟠 Hacker News トップストーリー

| #   | タイトル        | スコア | コメント数 |
| --- | --------------- | ------ | ---------- |
| 1   | [タイトル](URL) | ⬆ XXX  | 💬 XXX     |

### 🐦 X (Twitter) テックトレンド

| #   | トピック / 記事 | ソース       |
| --- | --------------- | ------------ |
| 1   | トピック名      | 検索結果より |
```

### B. ファイル保存（記事本文ダウンロード時）

記事本文を含む場合は、以下のディレクトリ構造でファイルを出力し `present_files` で提供する。

```
/mnt/user-data/outputs/tech-news-YYYY-MM-DD/
├── report.md                          # 統合レポート
├── zenn/
│   ├── 01_{slug}.md                   # 各記事の本文
│   └── ...
├── hatena/
│   ├── 01_{sanitized_title}.md
│   └── ...
├── hackernews/
│   ├── 01_{sanitized_title}.md
│   └── ...
└── x_twitter/
    └── summary.md                     # web_search結果サマリ
```

`report.md` にはすべての記事の一覧テーブルと、各記事ファイルへの相対リンクを含める。

## オプション

ユーザーの指示に応じて柔軟に対応する:

- **ソース指定**: 「Zennだけ」「HNとはてブ」など特定ソースのみ
- **キーワードフィルタ**: 「AIに関するものだけ」など
- **件数指定**: 「各ソース3件ずつ」「上位20件」など
- **出力形式**: 会話内マークダウン（デフォルト）/ .mdファイル保存
- **詳細モード**: description（概要文）も表示
- **簡易モード**: タイトルとURLのみ

## トラブルシューティング

- **はてブRSSがバイナリ返却**: `web_fetch` がXMLをバイナリ(application/xml)として返す場合がある。その場合:
  1. `web_search: "はてなブックマーク テクノロジー 人気エントリー 今日"` で直接検索
  2. `web_fetch: https://bookmark.hatenastaff.com/` で公式ブログの週間/月間ランキングを取得
  3. `web_fetch: https://www.daemonology.net/hn-daily/` 等のアグリゲーターサイトを参照
- **HN Firebase APIがrobots.txtでブロック**: `web_fetch` が ROBOTS_DISALLOWED エラーを返す場合:
  1. `web_search: "Hacker News top stories today"` で検索
  2. `web_fetch: https://www.daemonology.net/hn-daily/` (Hacker News Daily) で上位記事を取得
  3. `web_fetch: https://www.hntoplinks.com/` (HN Top Links) を参照
- **Zenn RSSは正常動作**: `web_fetch: https://zenn.dev/feed` で安定的にXMLが取得可能（text/xml）
- **X検索結果が少ない**: 検索クエリを英語・日本語両方で試す。`Twittrend.jp` で過去のトレンドデータも参照可能
