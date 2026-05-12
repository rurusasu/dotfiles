# X Twitter Source Workflow

Grok API `x_search` を使って X の投稿をリアルタイム検索し、結果を保存する手順。

## Prerequisites

- xAI APIキー: `op://Personal/xAI-Grok-Twitter/console/apikey`
- エンドポイント: `https://api.x.ai/v1/responses`
- モデル: `grok-4-1-fast`

## Steps

### Step 1: APIキー取得

```bash
XAI_API_KEY=$(op read 'op://Personal/xAI-Grok-Twitter/console/apikey')
```

### Step 2: x_search でトレンド検索

```bash
curl -s https://api.x.ai/v1/responses \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $XAI_API_KEY" \
  -d '{
    "model": "grok-4-1-fast",
    "input": [{"role": "user", "content": "今日のテック系・AI関連で話題のX投稿を10件、投稿者・本文・URL・エンゲージメント付きで教えて"}],
    "tools": [{"type": "x_search"}]
  }'
```

### Step 3: レスポンスから投稿情報を抽出

Grok のレスポンス（`output` 配列内の `message` タイプ）からテキストを解析し、以下を抽出:

- 投稿者名 / ハンドル
- 投稿本文
- URL (`https://x.com/{handle}/status/{id}`)
- エンゲージメント（いいね・RT・返信数）

### Step 4: ファイル保存

`x_twitter/summary.md` に保存する。`report.md` に相対リンクを記載する。

## 個別ツイートURL対応

ユーザーから `https://x.com/{handle}/status/{id}` を共有された場合:

1. URL を正規表現 `x\.com/([^/]+)/status/(\d+)` で検証
2. `allowed_x_handles` に handle を指定して `x_search` リクエスト
3. クエリに status ID を含めて特定投稿を取得

```bash
curl -s https://api.x.ai/v1/responses \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $XAI_API_KEY" \
  -d '{
    "model": "grok-4-1-fast",
    "input": [{"role": "user", "content": "Find the tweet by @{handle} with status ID {id}. Show full text, date, and engagement metrics."}],
    "tools": [{"type": "x_search", "allowed_x_handles": ["{handle}"]}]
  }'
```

## Fallback (APIキー不可時)

1. `web_search: "X Twitter tech AI trending today"`
2. `web_fetch: https://twittrend.jp` (日本のトレンドキーワード)
3. `web_fetch: https://getdaytrends.com/japan/` (トレンド+ツイート数)
4. `web_fetch: https://tweethunter.io/trending/ai` (AI系トレンドツイート)

## Summary Template

```markdown
---
source: X
date: YYYY-MM-DD
fetched_at: YYYY-MM-DD HH:MM JST
method: grok-api-x_search
---

## Trending Tech Posts

| #   | Author  | Post             | URL | Likes | RTs |
| --- | ------- | ---------------- | --- | ----- | --- |
| 1   | @handle | 投稿本文（要約） | URL | XX    | XX  |

## Notes

- Grok API x_search でリアルタイム取得
```
