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
      → 未処理のセッション JSONL を特定（SQLite DB で重複防止）
      → ingest_transcript(file_path=...) で Cognee にファイル単位で投入
      → 全セッション追加後、batch_cognify() で一括知識グラフ構築
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

**`initialHistoryLimit` vs `historyLimit` の違い**:

- `historyLimit`: セッション全体で保持する会話履歴の上限（Telegram: 50, Slack: 100）。既存設定。
- `initialHistoryLimit`: セッションリセット後、新セッション開始時に Slack API から取得するスレッド内メッセージ数の上限。`thread` セクション専用の新規設定。スレッドの文脈を復元するために使う。

## Cognee MCP ツール設計

既存の自己改善ループ 7 ツールは維持し、会話知識用の 3 ツールを追加する。

### 新規ツール

#### `ingest_transcript`

セッション JSONL を Cognee 知識グラフに取り込む。

```python
# パラメータ
agent_id: str       # エージェント ID（例: "slack-C0AK3SQKFV2"）
session_id: str     # セッション ID
file_path: str      # JSONL ファイルパス（コンテナ内パス、例: "/home/app/.openclaw/sessions/xxx.jsonl"）

# 処理
1. ファイルを読み込み（サイズ上限チェック: 10MB。超過時はチャンク分割）
2. cognee.add(content, dataset_name=f"sessions_{agent_id}")
3. cognee.cognify() は呼ばない（バッチ完了後に一括実行）

# 返値
{ "status": "ok", "chunks_added": 3, "agent_id": "...", "session_id": "..." }
```

**注意**: `cognify()` は全セッション追加後に `batch_cognify` で一括実行する。
セッション単位で `cognify()` を呼ぶとコストが高すぎるため。

#### `batch_cognify`

追加済みデータセットに対して知識グラフ構築を一括実行する。

```python
# パラメータ
dataset_prefix: str | None  # 対象データセット名のプレフィックス（省略で全体）

# 処理
1. cognee.cognify()  # 未処理の全データに対して実行

# 返値
{ "status": "ok", "nodes_created": 142, "datasets_processed": ["sessions_main", ...] }
```

#### `search_knowledge`

知識グラフを横断検索する。会話から抽出された知識（事実・決定・教訓・関係性）を検索する。

**`search_skill_history` との違い**: `search_skill_history` はスキル実行の成功/失敗履歴（Execution DataPoint）を検索する。`search_knowledge` は会話全体から抽出された知識グラフ（ノード・エッジ）を検索する。両者は補完関係にある。

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
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "node /app/data/hooks/log-skill-execution.js",
          },
        ],
      },
    ],
  },
}
```

フックスクリプトの処理:

1. 環境変数 `CLAUDE_TOOL_NAME` からツール名を受け取る（Claude Code PostToolUse フックの仕様）
2. ツール名が `cognee-skills__` プレフィックスを持つスキルツール実行かを判定
3. 該当すれば Cognee MCP の Streamable HTTP エンドポイント (`http://cognee-mcp-skills:8000/mcp`) に JSON-RPC リクエストを送信
   - HTTP POST で `{"jsonrpc": "2.0", "method": "tools/call", "params": {"name": "log_skill_execution", ...}}`
   - コンテナ内ネットワークなので Docker Compose の service name で直接通信可能
4. `log_skill_execution` 内部でスコア算出 → 閾値以下なら `get_skill_improvements` 自動発火

**エラーハンドリング**: フックの HTTP 呼び出しが失敗した場合はログ出力のみで処理を続行する（フック失敗でエージェントの応答をブロックしない）。

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

**重複防止**: SQLite DB (`/app/data/cognee-ingest-state.db`) で処理済みセッションを管理する。

- テーブル: `ingested_sessions(session_id TEXT PRIMARY KEY, agent_id TEXT, ingested_at TEXT, status TEXT)`
- `cognee-ingested.log` のようなテキストファイルはフォーマット未定義・ロック不可・git ノイズの原因となるため不採用
- SQLite は単一プロセスからのアクセス（cron ジョブ）なのでロック競合は発生しない

**エラーハンドリング・リトライ**:

- `ingest_transcript` 失敗時は `status = "failed"` で記録し、次回 cron 実行時にリトライ対象とする
- 3 回連続失敗したセッションは `status = "abandoned"` としてスキップし、警告を報告する
- JSONL の 7 日 prune 前に必ず取り込みが完了するよう、cron は毎日実行（7 回のリトライ機会）

## インフラ前提条件

### ボリュームマウント

`ingest_transcript` は Cognee MCP コンテナ内で実行されるが、セッション JSONL は OpenClaw コンテナの `openclaw-home` ボリューム内にある。Cognee MCP コンテナからセッションファイルを読めるようにするため、`openclaw-home` ボリュームを `cognee-mcp-skills` に読み取り専用でマウントする。

```yaml
# docker/cognee-skills/docker-compose.yml の cognee-mcp-skills サービスに追加
volumes:
  - ${SKILLS_PATH}:/skills:rw
  - openclaw-home:/openclaw-sessions:ro  # セッション JSONL 読み取り用

# volumes セクションに外部ボリュームを宣言
volumes:
  falkordb-data:
  ollama-data:
  openclaw-home:
    external: true
    name: openclaw_openclaw-home
```

`ingest_transcript` の `file_path` パラメータは Cognee コンテナ内のパス（`/openclaw-sessions/sessions/...`）を使用する。cron ジョブのプロンプトでパス変換を指示する。

### セッションディレクトリ構造

OpenClaw は全エージェントのセッション JSONL を `openclaw-home` ボリューム内に保存する。正確なディレクトリ構造は OpenClaw のバージョンに依存するが、cron ジョブのプロンプトでは `find` コマンドで `.jsonl` ファイルを探索する設計とし、特定のパス構造に依存しない。

### cron ジョブの実行エージェント

cron ジョブは `agentId: "main"` で実行する。main エージェントは `openclaw-home` ボリューム全体にアクセスできるため、全エージェントのセッションファイルを列挙可能。`sessionTarget: "isolated"` で他のセッションに影響を与えない。

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

cron ジョブ定義:

```jsonc
{
  "id": "...",
  "agentId": "main",
  "name": "cognee-daily-ingest",
  "enabled": true,
  "schedule": { "kind": "cron", "expr": "50 23 * * *", "tz": "Asia/Tokyo" },
  "sessionTarget": "isolated",
  "wakeMode": "now",
  "payload": {
    "kind": "agentTurn",
    "message": "...", // 下記プロンプト
  },
  "delivery": { "mode": "silent" },
}
```

プロンプトメッセージ:

```
Cognee daily ingest & skill improvement run.

1. Find all session JSONL files: `find /home/app/.openclaw -name '*.jsonl' -type f`
2. Check cognee-ingest-state.db for already-ingested sessions. Skip ingested, retry failed (max 3).
3. For each unprocessed session, call cognee-skills MCP `ingest_transcript` with file_path.
   IMPORTANT: Translate the path from OpenClaw container path to Cognee container path:
   /home/app/.openclaw/... → /openclaw-sessions/...
4. After all sessions are added, call `batch_cognify` to build the knowledge graph.
5. Call `search_knowledge` with queries: "user complaint", "error", "skill failure", "feedback".
6. For each skill mentioned in results, call `get_skill_status`. If score < 0.7, run `get_skill_improvements` → `amend_skill`.
7. Report summary: sessions ingested, skills improved, errors encountered.
```

### `entrypoint.sh`

gateway workspace AGENTS.md のポリシー注入セクションに Cognee フィードバックルールを追加。

## 対象スコープ

- 全エージェント（main, claude, gemini, Slack 専用 5 体）のセッションを Cognee に取り込む
- Cognee が知識の種類（事実・決定・タスク・教訓・関係性）を自動判定する
- `pruneAfter: "7d"` は変更しない

## 段階的リリース

パス 2 の暗黙的検知（AGENTS.md ルール）は初期リリースでは含めない。まず明示的な `/feedback` コマンドのみで運用し、フィードバック量とスコア変動を観察した上で暗黙的検知を追加する。

理由: 暗黙的検知は誤検知（ユーザーが単に話題を変えただけ等）のリスクがあり、過剰な `log_skill_execution(success=false)` がスコアを不当に下げる可能性がある。

## 注意事項

### PII（個人識別情報）

会話内容にはユーザーの個人情報が含まれる可能性がある。Cognee の知識グラフにはユーザー名・メールアドレス等がそのまま取り込まれるリスクがある。現時点では以下の前提で運用する:

- OpenClaw はセルフホスト環境（ユーザーの Docker Desktop）で動作しており、データは外部に送信されない
- Cognee のストレージ（FalkorDB, LanceDB）もローカルコンテナ内に閉じている
- 将来的にマルチユーザー化する場合は PII フィルタリングの追加が必要

### Cognee の `cognify()` チューニング

Cognee のデフォルト `cognify()` パイプラインは一般的なドキュメント向けに最適化されている。会話トランスクリプト（JSONL 形式、短いターンの繰り返し）に対しては最適でない可能性がある。初期リリース後に知識グラフの品質を評価し、必要に応じてカスタムパイプラインの導入を検討する。

## ファイル変更一覧

| ファイル                                                 | 変更内容                                                            |
| -------------------------------------------------------- | ------------------------------------------------------------------- |
| `docker/cognee-skills/skills_tools/__init__.py`          | `ingest_transcript`, `batch_cognify`, `search_knowledge` ツール登録 |
| `docker/cognee-skills/skills_tools/ingest_transcript.py` | 新規: JSONL ファイルパス → Cognee 知識グラフ取り込み                |
| `docker/cognee-skills/skills_tools/batch_cognify.py`     | 新規: 一括 cognify() 実行                                           |
| `docker/cognee-skills/skills_tools/search_knowledge.py`  | 新規: 知識グラフ横断検索                                            |
| `docker/cognee-skills/skills_tools/ingest_state.py`      | 新規: SQLite による取り込み状態管理                                 |
| `chezmoi/.chezmoidata/openclaw.yaml`                     | `slackThreadInitialHistoryLimit` 追加                               |
| `chezmoi/dot_openclaw/openclaw.docker.json.tmpl`         | `thread.initialHistoryLimit` 追加                                   |
| `chezmoi/dot_openclaw/cron/jobs.seed.json.tmpl`          | `cognee-daily-ingest` ジョブ追加                                    |
| `docker/cognee-skills/docker-compose.yml`                | `openclaw-home` ボリュームを ro マウント追加                        |
| `docker/openclaw/entrypoint.sh`                          | AGENTS.md にフィードバックルール注入                                |
| `docker/openclaw/hooks/log-skill-execution.js`           | 新規: PostToolUse フックスクリプト                                  |
| `docker/openclaw/Dockerfile`                             | `COPY hooks/ /app/data/hooks/` 追加（ビルド時配置）                 |
| `docs/chezmoi/dot_openclaw/07-channels.md`               | `initialHistoryLimit` のドキュメント追加                            |
