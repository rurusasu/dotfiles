# OpenClaw memorySearch + Secrets 統一 設計

## Summary

OpenClaw の builtin memorySearch を有効化し、Gemini embedding (`gemini-embedding-2-preview`) でセッションログ + memory ファイルのベクトル検索を実現する。併せて、環境変数で渡していたシークレットを Docker secrets に統一する。

## Approach

**builtin backend + Gemini embedding + secrets 統一**を採用。

- `memorySearch` を `agents.defaults` に追加（`provider: "gemini"`, `model: "gemini-embedding-2-preview"`）
- `sources: ["memory", "sessions"]` + `experimental.sessionMemory: true` でセッションログもインデックス対象
- `GEMINI_API_KEY` を Docker secret 経由で注入（1Password → `~/.openclaw/secrets/gemini_api_key`）
- `OPENAI_API_KEY` / `GEMINI_API_KEY` 環境変数を docker-compose.yml から削除（どちらも未使用: OpenAI は Codex OAuth 認証、Gemini CLI は OAuth `~/.gemini/oauth_creds.json` を使用しており、API キー環境変数は空だった）

### Why this approach

- **qmd 不要**: builtin backend で FTS + ベクトルハイブリッド検索が利用可能。追加バイナリのインストール不要
- **Gemini 無料枠**: Google AI Studio の embedding API は無料（1500 req/min）。個人利用で枠を超えることはない
- **自動 sync**: `sync.onSessionStart`, `sync.onSearch`, `sync.watch` がデフォルト有効。cron や entrypoint での手動 reindex 不要
- **secrets 統一**: 全シークレットを Docker secrets に寄せることで `docker inspect` での平文露出を防止

## Data Flow

```
起動時:
  entrypoint.sh → /run/secrets/gemini_api_key 読み取り → export GEMINI_API_KEY

セッション開始時 (sync.onSessionStart: true):
  OpenClaw → SQLite インデックス存在確認
    → なし: memory/*.md + sessions/*.jsonl をチャンク分割 → Gemini embedding API → SQLite に保存
    → あり: 差分チェック → 変更あれば増分 reindex

検索時 (memory_search ツール呼び出し):
  クエリテキスト → Gemini embedding API → ベクトル類似度 + BM25 ハイブリッド検索 → 上位結果をコンテキストに注入
```

## Changes

### 1. `chezmoi/dot_openclaw/openclaw.docker.json.tmpl`

`agents.defaults` 内に `memorySearch` セクションを追加:

```json
"memorySearch": {
  "enabled": true,
  "provider": "gemini",
  "model": "gemini-embedding-2-preview",
  "sources": ["memory", "sessions"],
  "experimental": {
    "sessionMemory": true
  },
  "query": {
    "hybrid": {
      "enabled": true
    }
  }
}
```

配置: `compaction` セクションの後。

### 2. `docker/openclaw/docker-compose.yml`

**削除** — `environment:` から:

```yaml
OPENAI_API_KEY: ${OPENAI_API_KEY:-}
GEMINI_API_KEY: ${GEMINI_API_KEY:-}
```

**追加** — `services.openclaw.secrets:` に:

```yaml
- gemini_api_key
```

**追加** — トップレベル `secrets:` に:

```yaml
gemini_api_key:
  file: ${OPENCLAW_GEMINI_API_KEY_FILE:?Set OPENCLAW_GEMINI_API_KEY_FILE in .env}
```

コメント更新: `OPENAI_API_KEY` 関連のコメント削除。

### 3. `docker/openclaw/entrypoint.sh`

既存の xai_api_key パターンに倣い、xAI ブロック直後（ログ出力の前）に secrets 読み取りブロックを追加:

```sh
_gemini_secret_file="/run/secrets/gemini_api_key"
if [ -f "$_gemini_secret_file" ]; then
  _gemini_key="$(cat "$_gemini_secret_file")"
  if [ -n "$_gemini_key" ]; then
    GEMINI_API_KEY="$_gemini_key"
    export GEMINI_API_KEY
  fi
fi
```

`_xai_status` パターンに倣い `_gemini_status` を初期化し、既存のログ行を拡張（別行ではなく同一行に統合）:

```sh
echo "[entrypoint] secrets: GITHUB_TOKEN=${_gh_len} chars, XAI_API_KEY=${_xai_status}, GEMINI_API_KEY=${_gemini_status}"
```

**Note**: `GEMINI_API_KEY` は embedding 専用。Gemini CLI エージェントセッションは OAuth (`~/.gemini/oauth_creds.json`) で認証しており、この環境変数は参照しない。OpenClaw の `google` プロバイダーは `process.env.GEMINI_API_KEY` を直接読み取るため、config テンプレートへのプレースホルダー追加は不要。

### 4. `scripts/powershell/handlers/Handler.OpenClaw.ps1`

**`WriteSecretFile` 呼び出し追加:**

```powershell
$this.WriteSecretFile(
    "op://Personal/OpenClawGeminiAPI/credential",
    "gemini_api_key",
    $false  # optional
)
```

**`EnsureEnvFile` に追加** — `OPENCLAW_XAI_API_KEY_FILE` 行の直後に:

```
OPENCLAW_GEMINI_API_KEY_FILE=$secretDir/gemini_api_key
```

### 5. `docker/openclaw/.env.example` (存在しない場合は新規作成)

`OPENCLAW_GEMINI_API_KEY_FILE` を追加。このファイルは手動セットアップ時のリファレンス用。通常は `Handler.OpenClaw.ps1` の `EnsureEnvFile()` が `.env` を自動生成するため、`.env.example` は直接使用されない。

## Storage

| データ                        | 保存先                                                          | 永続化        | git 管理                       |
| ----------------------------- | --------------------------------------------------------------- | ------------- | ------------------------------ |
| セッションログ (.jsonl)       | `openclaw-home` volume `/home/bun/.openclaw/agents/*/sessions/` | volume 存続中 | No                             |
| SQLite インデックス (.sqlite) | `openclaw-home` volume `/home/bun/.openclaw/memory/`            | volume 存続中 | No                             |
| memory ファイル (.md)         | `openclaw-data` volume `/app/data/workspace/memory/`            | volume 存続中 | workspace が git repo なら Yes |
| secrets ファイル              | ホスト `~/.openclaw/secrets/`                                   | 永続          | No (.gitignore)                |

## Configuration Defaults (変更不要)

以下は OpenClaw のデフォルト値がそのまま適用される。チューニングが必要になった場合に明示指定する。

| 設定                          | デフォルト         | 説明                               |
| ----------------------------- | ------------------ | ---------------------------------- |
| `sync.onSessionStart`         | true               | セッション開始時にインデックス同期 |
| `sync.onSearch`               | true               | 検索時に変更検知 → 遅延 reindex    |
| `sync.watch`                  | true               | ファイル変更を chokidar で監視     |
| `sync.sessions.deltaBytes`    | 100000             | reindex トリガーの最小バイト数     |
| `sync.sessions.deltaMessages` | 50                 | reindex トリガーの最小メッセージ数 |
| `query.hybrid.vectorWeight`   | (provider default) | ベクトル重み                       |
| `query.hybrid.textWeight`     | (provider default) | BM25 重み                          |
| `query.maxResults`            | 6                  | 検索結果の最大数                   |
| `cache.enabled`               | true               | embedding キャッシュ               |

## Security

- `GEMINI_API_KEY` は Docker secret 経由でのみ注入。環境変数としての直接指定を廃止
- `OPENAI_API_KEY` 環境変数を docker-compose.yml から削除
- 1Password アイテム `OpenClawGeminiAPI` (`4pjlxacdaqbtmas7rj3tb3mctm`) の `credential` フィールドから取得
- secrets ファイルは `~/.openclaw/secrets/` に保存（ホスト側、git 管理外）

## Risks

- **Gemini embedding API の可用性**: 無料枠は SLA なし。ダウン時は FTS-only にフォールバック（ベクトル検索不可、キーワード検索は継続）
- **初回インデックス構築のレイテンシ**: 24MB のセッションログの初回 embedding に数分かかる可能性。セッション開始時の初回レスポンスが遅延する
- **embedding モデルの preview ステータス**: `gemini-embedding-2-preview` は preview。GA 時にモデル名変更の可能性あり → config 変更のみで対応可能。モデルが削除された場合、OpenClaw は embedding API エラーを検知し FTS-only にフォールバックする（検索は継続可能）
