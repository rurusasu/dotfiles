# cognee-skills MCP — Self-Improving Skills via Docker MCP

## Summary

cognee-mcp をフォークし、スキルの自己改善ツールを追加した `cognee-mcp-skills` を Docker コンテナとして構築する。FalkorDB をグラフ+ベクトルのハイブリッドバックエンドとして使用し、全エージェント（Claude Code, Codex, Cursor, Claude Desktop, OpenClaw, Gemini CLI）から HTTP MCP で統一的にアクセスする。

## Approach

**cognee-mcp フォーク + FalkorDB ハイブリッド + Docker MCP (HTTP transport)**

### Why this approach

- **cognee-mcp 公式ベース**: 既存の `cognify`, `search`, `save_interaction` 等をそのまま活用。スキル改善ツールは自然な拡張として追加
- **FalkorDB ハイブリッド**: グラフDB + ベクトルDB を1コンテナで兼任。cognee 公式アダプタ（`cognee-community-hybrid-adapter-falkor`）あり
- **Docker MCP (HTTP)**: 全エージェントから統一的にアクセス可能。エージェントごとの個別実装不要
- **Gemini API Key 統一**: openclaw の qmd と同じ `GEMINI_API_KEY` + `gemini-embedding-2-preview` を共有。新規 API キー不要
- **Ollama オプション**: API キーなしで完全ローカル運用も可能（`--profile local`）

## Prerequisites

- `2026-03-15-openclaw-memorysearch-design` が実装済みであること（`gemini_api_key` Docker secret の設定を含む）
- cognee-mcp リポジトリのフォークが作成済みであること

## Out of Scope

- ChatGPT Actions（OpenAPI spec）の実装
- Ollama モデルの自動ダウンロード・管理
- 既存スキルの cognee への初期インポートの自動化（初回は手動で `cognify` を実行）
- スキルの新規作成機能（改善のみ）

## Architecture

```
┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│  Claude Code │  │   Codex     │  │   Cursor    │  │  OpenClaw   │
│  Claude DT   │  │  Gemini CLI │  │   ChatGPT   │  │  (Docker)   │
└──────┬───────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘
       │                 │                │                │
       └─────────────────┴────────────────┴────────────────┘
                                │
                         HTTP (port 8000)
                                │
                    ┌───────────▼───────────┐
                    │  cognee-mcp-skills    │
                    │  (Docker container)   │
                    │                       │
                    │  公式ツール:           │
                    │  - cognify, search    │
                    │  - save_interaction   │
                    │                       │
                    │  カスタムツール:        │
                    │  - log_skill_execution│
                    │  - search_skill_history│
                    │  - get_skill_status   │
                    │  - get_skill_improvements│
                    │  - amend_skill        │
                    │  - evaluate_amendment │
                    │  - rollback_skill     │
                    └───────────┬───────────┘
                                │
                         port 6379
                                │
                    ┌───────────▼───────────┐
                    │     FalkorDB          │
                    │  (グラフ + ベクトル)    │
                    └───────────────────────┘
```

OpenClaw からは Docker ネットワーク内で `http://cognee-mcp-skills:8000/mcp`、ローカルエージェントからは `http://localhost:8000/mcp` で接続。

ChatGPT は MCP 非対応のため、将来的に ChatGPT Actions（OpenAPI spec）で REST API を公開する形で対応。

## Data Model

FalkorDB のグラフに保存するノードとエッジ:

```
[Skill] ──HAS_VERSION──▶ [SkillVersion]
  │                           │
  │                     HAS_EXECUTION
  │                           │
  │                           ▼
  │                     [Execution]
  │                           │
  │                     HAS_FEEDBACK
  │                           │
  │                           ▼
  │                     [Feedback]
  │
  ├──HAS_AMENDMENT──▶ [Amendment]
  │                       │
  │                 BASED_ON_EXECUTIONS
  │                       │
  │                       ▼
  │                 [Execution] (複数)
  │
  └──RELATED_TO──▶ [Skill] (スキル間の関係)
```

### ノード定義

| ノード       | フィールド                                                                            |
| ------------ | ------------------------------------------------------------------------------------- |
| Skill        | id, name, source_path, agent_type (claude/codex/cursor/openclaw/gemini)               |
| SkillVersion | version, content (スキルディレクトリ全ファイルの内容), content_hash, created_at       |
| Execution    | id, agent, task_description, success (bool), error, duration_ms, timestamp            |
| Feedback     | type (user_correction/auto), message, timestamp                                       |
| Amendment    | id, diff, rationale, status (proposed/applied/rolled_back), score_before, score_after |

### Source of Truth

cognee グラフがスキルの正（Source of Truth）。スキルディレクトリの全ファイル（SKILL.md, scripts/_, references/_, assets/\*）を cognee の Custom DataPoint としてグラフに保存する。

```
cognee グラフ（正）
├── Skill DataPoint（SKILL.md 全文、scripts 内容、references 内容）
├── SkillVersion DataPoint（過去バージョンの全内容）
├── Execution DataPoint（実行ログ）
└── Amendment DataPoint（修正 diff + 根拠）
        │
        ▼ 同期（デプロイ）
dotfiles リポジトリ（各エージェントへの配布手段）
```

修正時は cognee 上でスキル内容を分析・修正し、ファイルシステムに書き出し → git commit → chezmoi で各エージェントに配布。

### 健全性スコア

- 直近 20 回の成功率（`success_rate`）+ ユーザー修正フィードバック数（`correction_penalty`）で算出
- `score = success_rate - (correction_count * 0.05)`（0.0〜1.0 の範囲にクランプ）
- スコアが **0.7 未満**になったら自動的に改善提案をトリガー
- N, 閾値, ペナルティ係数は環境変数で設定可能（`SKILL_HEALTH_WINDOW=20`, `SKILL_HEALTH_THRESHOLD=0.7`, `SKILL_CORRECTION_PENALTY=0.05`）

## MCP Tools

### 記録系

**`log_skill_execution`** — スキル実行後に呼ぶ

```json
{
  "skill_name": "dockerfile-optimization",
  "agent": "claude-code",
  "task_description": "Dockerfileのマルチステージビルド最適化",
  "success": false,
  "error": "hadolint DL3008 violation not caught",
  "duration_ms": 12500
}
```

### 検索・状態確認系

**`search_skill_history`** — 過去の実行履歴を検索

```json
{
  "skill_name": "dockerfile-optimization",
  "agent": "claude-code",
  "success": false,
  "limit": 20
}
```

**`get_skill_status`** — スキルの健全性サマリ

```json
{
  "skill_name": "dockerfile-optimization"
}
```

返却: 成功率、直近の失敗パターン、改善提案の有無

### 改善系

**`get_skill_improvements`** — 蓄積されたログから改善提案を生成

```json
{
  "skill_name": "dockerfile-optimization",
  "min_executions": 5
}
```

返却: diff 形式の修正案 + 根拠

**`amend_skill`** — 改善提案を適用（スキルディレクトリのファイルを書き換え）

```json
{
  "amendment_id": "amd_abc123"
}
```

**`evaluate_amendment`** — 修正後の実行結果を評価

```json
{
  "amendment_id": "amd_abc123"
}
```

返却: 修正前後のスコア比較、改善判定

**`rollback_skill`** — 修正が悪化した場合に前バージョンに戻す

```json
{
  "amendment_id": "amd_abc123"
}
```

### 自動改善フロー

```
log_skill_execution (毎回)
        │
        ▼
  成功率が閾値以下？ ──No──▶ 何もしない
        │
       Yes
        ▼
get_skill_improvements (自動トリガー)
        │
        ▼
  amend_skill (自動適用)
        │
        ▼
  次回以降の実行ログで自動評価
        │
        ▼
  スコア改善？ ──No──▶ rollback_skill
        │
       Yes
        ▼
  新バージョンとして確定
```

## Docker Configuration

### ディレクトリ構成

```
docker/cognee-skills/
├── docker-compose.yml
├── Dockerfile
├── .env.example
└── skills_tools/        ← カスタムツール実装
    ├── __init__.py
    ├── log_execution.py
    ├── search_history.py
    ├── skill_status.py
    ├── improvements.py
    ├── amend.py
    ├── evaluate.py
    └── rollback.py
```

### docker-compose.yml

```yaml
services:
  cognee-mcp-skills:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "8000:8000"
    environment:
      - TRANSPORT_MODE=http
      - LLM_PROVIDER=${LLM_PROVIDER:-gemini}
      - EMBEDDING_PROVIDER=${EMBEDDING_PROVIDER:-gemini}
      - EMBEDDING_MODEL=gemini-embedding-2-preview
      - GRAPH_DATABASE_PROVIDER=falkordb
      - GRAPH_DATABASE_URL=falkordb
      - GRAPH_DATABASE_PORT=6379
      - VECTOR_DB_PROVIDER=falkordb
      - VECTOR_DB_URL=falkordb
      - VECTOR_DB_PORT=6379
    secrets:
      - gemini_api_key
    depends_on:
      falkordb:
        condition: service_healthy
    volumes:
      - ${SKILLS_PATH}:/skills:rw # スキルディレクトリのみマウント
    networks:
      - cognee-network
    restart: unless-stopped

  falkordb:
    image: falkordb/falkordb:v4.4.1
    ports:
      - "6379:6379"
    volumes:
      - falkordb-data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 3
    networks:
      - cognee-network
    restart: unless-stopped

  # オプション: API キーなしのローカル LLM
  ollama:
    image: ollama/ollama:latest
    profiles: ["local"]
    ports:
      - "11434:11434"
    volumes:
      - ollama-data:/root/.ollama
    networks:
      - cognee-network
    restart: unless-stopped

networks:
  cognee-network:
    driver: bridge

volumes:
  falkordb-data:
  ollama-data:

secrets:
  gemini_api_key:
    file: ${OPENCLAW_GEMINI_API_KEY_FILE}
```

### LLM プロバイダー切り替え

`.env` で制御:

```bash
# Gemini（デフォルト）
LLM_PROVIDER=gemini
EMBEDDING_PROVIDER=gemini

# ローカル（Ollama）に切り替え
# LLM_PROVIDER=ollama
# LLM_ENDPOINT=http://ollama:11434/v1
# EMBEDDING_PROVIDER=ollama
# EMBEDDING_MODEL=nomic-embed-text:latest
# docker compose --profile local up
```

### OpenClaw との接続

既存の `docker/openclaw/docker-compose.yml` に external network を追加:

```yaml
networks:
  cognee-network:
    external: true
```

OpenClaw から `http://cognee-mcp-skills:8000/mcp` で到達可能。

## Agent Integration

### MCP サーバー登録

`chezmoi/.chezmoidata/mcp_servers.yaml` に追加:

```yaml
cognee-skills:
  type: url
  url: http://localhost:8000/mcp
  supports:
    - codex
    - claude
    - cursor
    - gemini
```

chezmoi テンプレートで各ツールの設定ファイルに自動展開。

### OpenClaw 用（Docker ネットワーク内）

`chezmoi/dot_openclaw/openclaw.docker.json.tmpl` の mcpServers に追加:

```json
{
  "cognee-skills": {
    "type": "url",
    "url": "http://cognee-mcp-skills:8000/mcp"
  }
}
```

### ChatGPT

MCP 非対応。将来的に ChatGPT Actions（OpenAPI spec）で対応。当面スキップ。

## Environment Variables

qmd と統一。新規 API キー・secret の追加はゼロ。

| 変数               | 値                         | 共有元                 |
| ------------------ | -------------------------- | ---------------------- |
| GEMINI_API_KEY     | Docker secret 経由         | openclaw と同じ secret |
| EMBEDDING_MODEL    | gemini-embedding-2-preview | qmd と同じモデル       |
| LLM_PROVIDER       | gemini                     | .env で切り替え可能    |
| EMBEDDING_PROVIDER | gemini                     | .env で切り替え可能    |

## Error Handling

### スキル修正の失敗

- `amend_skill` がファイル書き換えに失敗 → Amendment ステータスを `failed` に、ファイルは変更なし
- git commit/push 失敗 → 修正はグラフ上に保持、次回リトライ可能

### FalkorDB ダウン

- `log_skill_execution` → ログをローカルファイルにバッファ、復旧後にグラフへ投入
- `search` / `get_skill_status` → エラーを返す（degraded mode）

### 自動改善の暴走防止

- 同一スキルへの修正は **24時間に1回まで**
- 連続3回の修正でスコアが改善しなければ自動修正を停止、通知のみに切り替え
- rollback 後は手動承認がないと再度自動修正しない

### embedding モデル変更

- qmd と cognee で同じモデルを使うので、モデル変更時は一括で再インデックス
- `gemini-embedding-2-preview` が GA になった場合、環境変数を1箇所変えるだけ

## Storage

| データ                          | 保存先                                          | 永続化                                      |
| ------------------------------- | ----------------------------------------------- | ------------------------------------------- |
| スキルグラフ（ノード・エッジ）  | FalkorDB volume (`falkordb-data`)               | Docker named volume                         |
| ベクトルインデックス            | FalkorDB volume (`falkordb-data`)               | Docker named volume                         |
| スキルファイル（デプロイ先）    | ホスト側 skills ディレクトリ                    | git 管理                                    |
| FalkorDB ダウン時のバッファログ | cognee-mcp-skills コンテナ内 `/tmp/skill-logs/` | tmpfs（再起動で消失、復旧後にグラフへ投入） |

### バックアップ

- FalkorDB: `redis-cli BGSAVE` で RDB スナップショットを取得。cron で日次バックアップ推奨
- スキルファイル: dotfiles リポジトリの git 履歴がバックアップを兼ねる
- グラフデータの完全喪失時: スキルファイル（git）から `cognify` で再構築可能。実行ログは失われる

## Changes

### 1. `docker/cognee-skills/docker-compose.yml`（新規作成）

上記 Docker Configuration セクションの通り。

### 2. `docker/cognee-skills/Dockerfile`（新規作成）

cognee-mcp フォークをベースに、FalkorDB アダプタとカスタムツールを追加するビルド定義。

### 3. `docker/cognee-skills/.env.example`（新規作成）

```
LLM_PROVIDER=gemini
EMBEDDING_PROVIDER=gemini
EMBEDDING_MODEL=gemini-embedding-2-preview
SKILLS_PATH=../../chezmoi/dot_claude/skills
OPENCLAW_GEMINI_API_KEY_FILE=~/.openclaw/secrets/gemini_api_key
SKILL_HEALTH_WINDOW=20
SKILL_HEALTH_THRESHOLD=0.7
SKILL_CORRECTION_PENALTY=0.05
```

### 4. `docker/cognee-skills/skills_tools/`（新規作成）

7つのカスタムツール実装（MCP Tools セクション参照）。

### 5. `chezmoi/.chezmoidata/mcp_servers.yaml`

**追加**:

```yaml
cognee-skills:
  type: url
  url: http://localhost:8000/mcp
  supports:
    - codex
    - claude
    - cursor
    - gemini
```

### 6. `chezmoi/dot_openclaw/openclaw.docker.json.tmpl`

**追加** — `mcpServers` セクションに:

```json
"cognee-skills": {
  "type": "url",
  "url": "http://cognee-mcp-skills:8000/mcp"
}
```

### 7. `docker/openclaw/docker-compose.yml`

**追加** — `networks` セクション:

```yaml
networks:
  default:
  cognee-network:
    external: true
```

**追加** — `services.openclaw.networks`:

```yaml
networks:
  - default
  - cognee-network
```

cognee-mcp-skills が起動していない場合でも OpenClaw は正常に起動する（MCP 接続は lazy）。

### 8. `scripts/powershell/handlers/Handler.CogneeSkills.ps1`（新規作成）

OpenClaw ハンドラーと同様の2層ゲート（interaction gate + infrastructure gate）で cognee-skills コンテナのビルド・起動を管理。

## Risks

- **cognee-mcp フォーク管理**: 公式アップデートとの差分が広がるリスク。定期的な upstream マージで対応
- **FalkorDB コミュニティアダプタの安定性**: `cognee-community-hybrid-adapter-falkor` は公式サポートではない。問題発生時は Kuzu + LanceDB（デフォルト）にフォールバック可能
- **自動修正の品質**: LLM による改善提案が的外れな場合がある。暴走防止ルール + rollback で対応
- **Gemini embedding API の可用性**: 無料枠は SLA なし。ダウン時は検索不可だが、ログ記録はローカルバッファで継続
- **cognee dev ビルド**: cognee 自体がまだ dev ビルド（0.5.4.dev2）。破壊的変更の可能性あり。フォーク時に特定コミットを pin して対応
- **FalkorDB ポート競合**: デフォルト 6379 は Redis と同じ。ホスト側で Redis を使用している場合は `16379:6379` にマッピング変更が必要
- **Source of Truth の二重性**: cognee グラフが正だが、スキルファイルの直接編集（git push）も可能。衝突時は git 側を優先し、次回 `cognify` で再取り込み
