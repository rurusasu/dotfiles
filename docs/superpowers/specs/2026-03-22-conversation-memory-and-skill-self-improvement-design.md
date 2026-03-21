# 会話記憶アーキテクチャ & スキル自己改善ループ設計

## 概要

OpenClaw の全チャットツール会話を構造化知識として永久保持し、Cognee の知識グラフを活用してスキルの自己改善ループを自律的に回す仕組みを構築する。

### 背景

- セッション JSONL は自動保存されているが `pruneAfter: "7d"` で 7 日後に削除される
- QMD（BM25+vector）は `sessionMemory: true` でセッション横断検索が可能だが、検索対象は JSONL 存続期間に依存する
- Cognee MCP はスキル自己改善用の 7 ツールを持つが、`log_skill_execution` を呼ぶ仕組みがなく一度もループが回っていない
- Slack スレッドではセッションリセット後に文脈が失われる（`initialHistoryLimit` 未明示、デフォルト 20 件）

### 目標

1. 会話履歴を知識として永久保持する（生データの長期保持は不要）
2. Cognee のスキル自己改善ループを自律的に回す
3. Slack スレッドのセッションリセット後に文脈を復元する

## アーキテクチャ

### 3 層会話記憶

| 層   | コンポーネント       | 保持期間                        | 内容                                     |
| ---- | -------------------- | ------------------------------- | ---------------------------------------- |
| Hot  | JSONL（生データ）    | 7 日（`pruneAfter: "7d"` 維持） | 全メッセージ。直近の文脈検索用           |
| Warm | QMD（BM25+vector）   | JSONL 存続期間                  | セッション横断のキーワード・ベクトル検索 |
| Cold | Cognee（知識グラフ） | 永久                            | 会話から抽出した知識・関係性・決定事項   |

### データフロー

```
会話発生
  → JSONL 自動保存（既存）
  → QMD がインデックス（既存）
  → 毎日 23:50 JST、cron ジョブがエージェントを起動（新規）
      → 未処理のセッション JSONL を特定（cognee-ingested.log で重複防止）
      → ingest_transcript で Cognee に投入
      → Cognee が cognee.add() → cognee.cognify() で知識グラフ構築
      → search_knowledge + get_skill_status で問題スキルを検出
      → 該当スキルに get_skill_improvements → amend_skill を実行
  → 7 日後に JSONL が自動削除
      → 知識は Cognee に残っているため情報は失われない
```

### Slack スレッドの文脈復元

セッションリセット後にスレッドへ新メッセージが来た場合:

1. **Hot 層**: Slack API → `initialHistoryLimit` 件の生メッセージ取得（50 件に設定）
2. **Warm 層**: QMD `sessionMemory` → 過去セッション JSONL から関連文脈を自動注入
3. **Cold 層**: エージェントが必要に応じて `search_knowledge` で Cognee を検索

## Cognee MCP ツール設計

既存の自己改善ループ 7 ツールは維持し、会話知識用の 2 ツールを追加する。

### 新規ツール

#### `ingest_transcript`

セッション JSONL を Cognee 知識グラフに取り込む。

```python
# パラメータ
agent_id: str       # エージェント ID（例: "slack-C0AK3SQKFV2"）
session_id: str     # セッション ID
transcript: str     # JSONL 文字列（セッション全文）

# 処理
1. cognee.add(transcript, dataset_name=f"sessions_{agent_id}")
2. cognee.cognify()

# 返値
{ "status": "ok", "nodes_created": 42, "agent_id": "...", "session_id": "..." }
```

#### `search_knowledge`

知識グラフを横断検索する。

```python
# パラメータ
query: str           # 自然言語クエリ
agent_id: str | None # 特定エージェントに絞る（省略で全体）
source: str | None   # "sessions" | "skills" | None（全体）
limit: int = 10

# 処理
1. cognee.search(query_type=SearchType.CHUNKS, query_text=query, datasets=...)

# 返値
{ "results": [{ "content": "...", "score": 0.92, "source": "...", ... }] }
```

### 既存ツール（維持）

| ツール                   | 用途                                                |
| ------------------------ | --------------------------------------------------- |
| `log_skill_execution`    | スキル実行結果を記録。スコア < 0.7 で改善を自動発火 |
| `search_skill_history`   | 実行履歴の検索                                      |
| `get_skill_status`       | ヘルススコア算出                                    |
| `get_skill_improvements` | 改善提案の生成（RAG_COMPLETION）                    |
| `amend_skill`            | スキルファイルの修正適用                            |
| `evaluate_amendment`     | 修正前後のスコア比較                                |
| `rollback_skill`         | 修正のロールバック（3 回連続改善なしで自動）        |

## 自動化の 3 パス

### パス 1: 即時（PostToolUse フック）

スキルツール実行後に自動で `log_skill_execution` を呼ぶ。

```jsonc
// コンテナ内 /home/app/.claude/settings.json
{
  "hooks": {
    "PostToolUse": [
      {
        "hook": "node /app/data/hooks/log-skill-execution.js",
      },
    ],
  },
}
```

フックスクリプトの処理:

1. 実行されたツール名を受け取る
2. MCP 経由のスキルツール実行かどうかを判定
3. 該当すれば `cognee-skills` MCP の `log_skill_execution` を HTTP POST で呼ぶ
4. `log_skill_execution` 内部でスコア算出 → 閾値以下なら `get_skill_improvements` 自動発火

### パス 2: 即時（ユーザーフィードバック）

ユーザーがスキル出力に対して修正を指摘した場合に即座に記録する。2 つの経路:

**暗黙的検知（AGENTS.md ルール）:**

gateway workspace の AGENTS.md に以下を注入（`entrypoint.sh` のポリシー注入セクション）:

```markdown
## Cognee スキルフィードバック

- スキル実行後にユーザーが出力に対して修正・やり直し・不満を表明した場合、
  直前に使用したスキルに対して cognee-skills MCP の log_skill_execution を
  success=false, error="ユーザー指摘: <内容の要約>" で呼び出すこと
- /feedback <スキル名> <問題内容> コマンドでも明示的にフィードバックを記録できる
```

**明示的コマンド:**

ユーザーが `/feedback <スキル名> <問題内容>` で直接フィードバックを送信。

どちらの経路でも `log_skill_execution(success=false)` が呼ばれ、スコアが下がり、改善トリガーが発火する。

### パス 3: バッチ（毎日 cron）

毎日 23:50 JST に cron ジョブがエージェントを起動し、以下を実行:

1. 全エージェントの未処理セッション JSONL を `ingest_transcript` で Cognee に投入
2. `search_knowledge` でユーザーフィードバック・エラーパターンを検索
3. `get_skill_status` で該当スキルのスコアを確認
4. スコア低下スキルに `get_skill_improvements` → `amend_skill` を実行
5. 結果を報告

重複防止: ワークスペースの `cognee-ingested.log` に処理済みセッション ID を記録。

## 設定変更

### `openclaw.yaml`

```yaml
channels:
  slackThreadInitialHistoryLimit: 50 # 新規追加
```

### `openclaw.docker.json.tmpl`

Slack thread セクションに `initialHistoryLimit` を追加:

```jsonc
"thread": {
  "historyScope": "thread",
  "inheritParent": false,
  "initialHistoryLimit": {{ .openclaw.channels.slackThreadInitialHistoryLimit }}
}
```

### `cron/jobs.seed.json.tmpl`

`cognee-daily-ingest` ジョブを追加（毎日 23:50 JST、全エージェント対象）。

### `entrypoint.sh`

gateway workspace AGENTS.md のポリシー注入セクションに Cognee フィードバックルールを追加。

## 対象スコープ

- 全エージェント（main, claude, gemini, Slack 専用 5 体）のセッションを Cognee に取り込む
- Cognee が知識の種類（事実・決定・タスク・教訓・関係性）を自動判定する
- `pruneAfter: "7d"` は変更しない

## ファイル変更一覧

| ファイル                                                 | 変更内容                                           |
| -------------------------------------------------------- | -------------------------------------------------- |
| `docker/cognee-skills/skills_tools/__init__.py`          | `ingest_transcript`, `search_knowledge` ツール登録 |
| `docker/cognee-skills/skills_tools/ingest_transcript.py` | 新規: JSONL → Cognee 知識グラフ取り込み            |
| `docker/cognee-skills/skills_tools/search_knowledge.py`  | 新規: 知識グラフ横断検索                           |
| `chezmoi/.chezmoidata/openclaw.yaml`                     | `slackThreadInitialHistoryLimit` 追加              |
| `chezmoi/dot_openclaw/openclaw.docker.json.tmpl`         | `thread.initialHistoryLimit` 追加                  |
| `chezmoi/dot_openclaw/cron/jobs.seed.json.tmpl`          | `cognee-daily-ingest` ジョブ追加                   |
| `docker/openclaw/entrypoint.sh`                          | AGENTS.md にフィードバックルール注入               |
| `/app/data/hooks/log-skill-execution.js`                 | 新規: PostToolUse フックスクリプト                 |
| `docs/chezmoi/dot_openclaw/07-channels.md`               | `initialHistoryLimit` のドキュメント追加           |
