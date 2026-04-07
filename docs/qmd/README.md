# qmd

[tobi/qmd](https://github.com/tobi/qmd) は、マークダウンノートやドキュメントをローカルで検索するオンデバイス検索エンジン。
BM25 全文検索、ベクトル意味検索、LLM リランキングを組み合わせたハイブリッド検索を提供する。

## 目次

- [アーキテクチャ](#アーキテクチャ)
- [インストール](#インストール)
- [CLI コマンド](#cli-コマンド)
- [環境変数](#環境変数)
- [設定ファイル (qmd.yml)](#設定ファイル-qmdyml)
- [MCP サーバー](#mcp-サーバー)
- [データ保存パス](#データ保存パス)
- [このリポジトリでの設定](#このリポジトリでの設定)

---

## アーキテクチャ

### 検索パイプライン

```
クエリ入力
    │
    ▼
┌─────────────────────┐
│  1. クエリ展開       │  LLM が 2 つの代替クエリを生成
│     (Query Expansion)│  オリジナルクエリは ×2 の重み
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  2. 並列検索         │  各クエリで BM25 + ベクトル検索を同時実行
│     (Parallel)       │
│  ┌────────┐ ┌──────┐│
│  │ BM25   │ │Vector││
│  │ (FTS5) │ │Search││
│  └────────┘ └──────┘│
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  3. RRF 融合         │  Reciprocal Rank Fusion (k=60)
│     + 順位ボーナス    │  #1: +0.05, #2-3: +0.02
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  4. LLM リランキング │  yes/no スコアリング (logprobs)
│     (Reranking)      │
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  5. スコアブレンド    │  順位に応じた重み配分
│  #1-3:  75% 検索 / 25% リランカー
│  #4-10: 60% 検索 / 40% リランカー
│  #11+:  40% 検索 / 60% リランカー
└─────────────────────┘
```

### モデル構成

| モデル | デフォルト | サイズ | 用途 |
|--------|-----------|--------|------|
| Embedding | embeddinggemma-300M (Q8_0) | ~300MB | ベクトル埋め込み生成 |
| Reranker | Qwen3-Reranker-0.6B (Q8_0) | ~640MB | 検索結果のリランキング |
| Generation | qmd-query-expansion-1.7B (Q4_K_M) | ~1.1GB | クエリ展開（専用ファインチューニング） |

モデルは初回使用時に HuggingFace から自動ダウンロードされ、`~/.cache/qmd/models/` にキャッシュされる。
推論は [node-llama-cpp](https://github.com/withcatai/node-llama-cpp) (GGUF 形式) で実行。

### 対応モデルファミリー

**Embedding** はコード内でプロンプト形式を切り替える:

| ファミリー | 検出条件 | クエリプロンプト | ドキュメントプロンプト |
|-----------|---------|----------------|---------------------|
| EmbeddingGemma (デフォルト) | URI が Qwen パターンに非該当 | `task: search result \| query: {query}` | `title: {title} \| text: {content}` |
| Qwen3-Embedding | URI に `qwen.*embed` を含む | `Instruct: Retrieve relevant documents...\nQuery: {query}` | テキストのみ |

**注意**: nomic-embed, bge, gte, mxbai 等は対応プロンプト形式がないため正常動作しない。

### SQLite スキーマ

```
collections          — インデックス対象ディレクトリ (名前/glob パターン)
path_contexts        — コンテキスト説明文 (仮想パス)
documents            — ドキュメント本体 + メタデータ, docid (6文字ハッシュ)
documents_fts        — FTS5 全文検索インデックス
content_vectors      — チャンク: hash, seq, pos, ~900 トークン
vectors_vec          — sqlite-vec ベクトルインデックス
llm_cache            — LLM レスポンスキャッシュ
```

### チャンキング

ドキュメントは ~900 トークン境界で分割。ブレイクポイントのスコアリング:

| 要素 | スコア |
|------|--------|
| H1 見出し | 100 |
| H2 | 90 |
| H3 | 80 |
| コードブロック | 80 |
| H4 | 70 |
| 水平線 | 60 |
| H5 / H6 | 60 / 50 |
| 空行 | 20 |
| リスト項目 | 5 |
| 改行 | 1 |

**AST モード** (`.ts`, `.tsx`, `.js`, `.jsx`, `.py`, `.go`, `.rs`):
class/interface/struct: 100, function: 90, type/enum: 80, import: 60

---

## インストール

```bash
# グローバルインストール
pnpm add -g @tobilu/qmd

# 直接実行 (インストール不要)
npx @tobilu/qmd [command]
bunx @tobilu/qmd [command]
```

**要件**: Node.js >= 22 または Bun >= 1.0.0

macOS の場合は Homebrew SQLite も必要:

```bash
brew install sqlite
```

---

## CLI コマンド

### 検索コマンド

#### `qmd query <query>` — ハイブリッド検索 (推奨)

クエリ展開 + BM25 + ベクトル検索 + LLM リランキングの全機能を使用。

```bash
qmd query "認証フローの実装方法"
qmd query "auth middleware" -n 10 -c docs --explain
```

| オプション | 説明 | デフォルト |
|-----------|------|-----------|
| `-n <num>` | 最大結果数 | 5 (--files/--json 時は 20) |
| `--all` | 全結果を返す | — |
| `--min-score <num>` | 最小スコア閾値 | 0 |
| `--full` | スニペットではなく全文を表示 | — |
| `-C, --candidate-limit <n>` | リランキング候補数上限 | 40 |
| `--no-rerank` | LLM リランキングをスキップ (RRF のみ) | — |
| `--intent <text>` | 検索意図 (曖昧さ解消用) | — |
| `--chunk-strategy` | `auto` (AST) または `regex` | regex |
| `-c, --collection <name>` | コレクションでフィルタ (複数可) | — |
| `--explain` | スコア内訳を表示 | — |

**構造化クエリ構文**: `lex:`, `vec:`, `hyde:`, `intent:`, `expand:` プレフィックスで検索タイプを指定可能。

#### `qmd search <query>` — BM25 全文検索

キーワードベースの検索。LLM を使用しない。

```bash
qmd search "connection pool timeout"
```

| オプション | 説明 | デフォルト |
|-----------|------|-----------|
| `-n <num>` | 最大結果数 | 5 |
| `--all` | 全結果を返す | — |
| `--min-score <num>` | 最小スコア閾値 | — |
| `--full` | 全文表示 | — |
| `-c, --collection <name>` | コレクションフィルタ | — |

#### `qmd vsearch <query>` — ベクトル検索

意味的類似度による検索。

```bash
qmd vsearch "ユーザー認証の仕組み"
```

| オプション | 説明 | デフォルト |
|-----------|------|-----------|
| `-n <num>` | 最大結果数 | 5 |
| `--all` | 全結果を返す | — |
| `--min-score <num>` | 最小類似度スコア | — |
| `--full` | 全文表示 | — |
| `-c, --collection <name>` | コレクションフィルタ | — |
| `--intent <text>` | 検索意図 | — |

#### 出力フォーマット (全検索コマンド共通)

| フラグ | 形式 |
|--------|------|
| `--csv` | CSV |
| `--json` | JSON 配列 |
| `--md` | Markdown |
| `--xml` | XML |
| `--files` | ファイルリスト (docid + スコア) |

---

### ドキュメント取得

#### `qmd get <file>[:line] [-l N]`

単一ドキュメントを取得。行指定でスライス可能。

```bash
qmd get docs/readme.md              # 全文
qmd get docs/readme.md:50 -l 20     # 50行目から20行
qmd get "#abc123"                    # docid で取得
qmd get "qmd://docs/readme.md"      # 仮想パス
```

| オプション | 説明 |
|-----------|------|
| `-l, --l <num>` | 表示行数上限 |
| `--from <num>` | 開始行番号 |
| `--line-numbers` | 行番号を付与 |

#### `qmd multi-get <pattern>`

glob パターンまたはカンマ区切りで一括取得。

```bash
qmd multi-get "docs/**/*.md"
qmd multi-get "file1.md,file2.md" --json
```

| オプション | 説明 | デフォルト |
|-----------|------|-----------|
| `-l, --l <num>` | ドキュメントあたりの最大行数 | — |
| `--max-bytes <num>` | ファイルサイズ上限 (超過はスキップ) | 10KB |

---

### コレクション管理

#### `qmd collection add <path> [globPattern] [--name <name>]`

新しいコレクションを作成してインデックス。

```bash
qmd collection add ~/notes --name my-notes
qmd collection add ./docs "**/*.md" --name project-docs
```

#### `qmd collection list`

全コレクションをメタデータ付きで表示。

#### `qmd collection remove <name>`

コレクションと関連ドキュメントを削除。

#### `qmd collection rename <oldName> <newName>`

コレクション名を変更 (仮想パスも更新)。

#### `qmd ls [collection[/path]]`

コレクション内のインデックス済みファイルを一覧表示。

```bash
qmd ls                    # 全コレクション
qmd ls docs               # docs コレクション
qmd ls docs/api           # docs/api 以下
```

---

### コンテキスト管理

コレクションパスに人間が書いた説明文を付与する。検索精度向上に寄与。

#### `qmd context add [path] <contextText>`

```bash
qmd context add / "社内エンジニアリングドキュメント"        # グローバル
qmd context add docs/api "REST API リファレンス"           # パス指定
qmd context add "qmd://docs/api" "REST API リファレンス"   # 仮想パス
```

#### `qmd context list`

全コンテキストをコレクション別に表示。

#### `qmd context remove <path>`

指定パスのコンテキストを削除。

---

### メンテナンス

#### `qmd update [--pull]`

全コレクションを再インデックス。

| オプション | 説明 |
|-----------|------|
| `--pull` | 各コレクションで `git pull` を実行してからインデックス |

#### `qmd embed [-f]`

ベクトル埋め込みを生成・更新。

| オプション | 説明 |
|-----------|------|
| `-f, --force` | 全ハッシュを強制再埋め込み (既存ベクトルをクリア) |
| `--max-docs-per-batch <n>` | バッチあたりのドキュメント数 |
| `--max-batch-mb <n>` | バッチあたりのバイト数上限 |
| `--chunk-strategy` | `auto` (AST) または `regex` |

**重要**: 埋め込みモデルを変更した場合は `qmd embed -f` で再インデックスが必須。

#### `qmd status`

インデックスの健全性、コレクション統計、モデル/デバイス情報を表示。
MCP デーモンの状態、GPU/VRAM 情報も確認可能。

#### `qmd cleanup`

キャッシュクリアとデータベースの VACUUM を実行。

---

### スキル管理

#### `qmd skill show`

組み込み QMD スキルの内容を表示。

#### `qmd skill install [--global] [-f] [--yes]`

QMD スキルをインストール。

| オプション | 説明 |
|-----------|------|
| `--global` | `~/.agents/skills/qmd` にインストール (デフォルト: `./.agents/skills/qmd`) |
| `-f, --force` | 既存スキルを上書き |
| `--yes` | Claude シンボリックリンク作成を自動承認 |

---

### グローバルオプション

| オプション | 説明 |
|-----------|------|
| `--index <name>` | 名前付きインデックスを使用 (デフォルト: "index") |
| `-h, --help` | ヘルプ表示 |
| `-v, --version` | バージョン表示 |

---

## 環境変数

### qmd 固有

| 変数 | デフォルト | 説明 |
|------|-----------|------|
| `QMD_EMBED_MODEL` | `hf:ggml-org/embeddinggemma-300M-GGUF/embeddinggemma-300M-Q8_0.gguf` | 埋め込みモデル URI |
| `QMD_GENERATE_MODEL` | `hf:tobil/qmd-query-expansion-1.7B-gguf/qmd-query-expansion-1.7B-q4_k_m.gguf` | クエリ展開モデル URI |
| `QMD_RERANK_MODEL` | `hf:ggml-org/Qwen3-Reranker-0.6B-Q8_0-GGUF/qwen3-reranker-0.6b-q8_0.gguf` | リランキングモデル URI |
| `QMD_LLAMA_GPU` | 自動検出 | `false`/`off`/`0` で CPU のみ |
| `QMD_EXPAND_CONTEXT_SIZE` | `2048` | クエリ展開のコンテキストサイズ (トークン) |
| `QMD_RERANK_CONTEXT_SIZE` | `4096` | リランキングのコンテキストサイズ (トークン) |
| `QMD_EMBED_CONTEXT_SIZE` | `2048` | 埋め込みのコンテキストサイズ (トークン) |
| `QMD_EDITOR_URI` | `vscode://file/{path}:{line}:{col}` | ターミナル検索結果のエディタリンク |
| `QMD_CONFIG_DIR` | `$XDG_CONFIG_HOME/qmd` | 設定ディレクトリ |

### エディタ URI テンプレート

| エディタ | URI |
|---------|-----|
| VS Code | `vscode://file/{path}:{line}:{col}` |
| Cursor | `cursor://file/{path}:{line}:{col}` |
| Zed | `zed://file/{path}:{line}:{col}` |
| Sublime Text | `subl://open?url=file://{path}&line={line}` |

プレースホルダー: `{path}` (ファイルパス), `{line}` (行番号), `{col}` / `{column}` (列番号)

### 標準環境変数

| 変数 | デフォルト | 説明 |
|------|-----------|------|
| `XDG_CACHE_HOME` | `~/.cache` | キャッシュルート → `~/.cache/qmd/` |
| `XDG_CONFIG_HOME` | `~/.config` | 設定ルート → `~/.config/qmd/` |
| `NO_COLOR` | 未設定 | セットでカラー出力無効 |
| `CI` | 未設定 | `true` で LLM 操作をブロック |
| `INDEX_PATH` | 未設定 | SQLite パス上書き (テスト用) |
| `BREW_PREFIX` | `/opt/homebrew` | Homebrew プレフィックス (macOS) |

---

## クエリ構文

### 検索タイプ

`qmd query` では構造化クエリ構文でサブクエリのタイプを指定できる。

| タイプ | プレフィックス | 用途 | 例 |
|--------|-------------|------|-----|
| **lex** | `lex:` | 完全一致、名前、コード識別子 | `lex: "connection pool" timeout` |
| **vec** | `vec:` | 自然言語の質問 | `vec: 認証の仕組みは？` |
| **hyde** | `hyde:` | 仮想回答パッセージ (50-100語) | `hyde: The pool uses a 30s timeout...` |
| **expand** | `expand:` | LLM による自動展開 | `expand: auth flow` |
| **intent** | `intent:` | 検索意図 (曖昧さ解消) | `intent: web performance` |

### 複数行クエリ

```
intent: web パフォーマンス
lex: "connection pool" timeout
vec: コネクションプールのタイムアウト処理は？
hyde: コネクションプールは30秒のタイムアウトと指数バックオフを使用する...
```

- 最初のクエリは RRF で 2 倍の重み
- `intent:` は 1 行のみ
- `expand:` は型付きクエリと混在不可
- 型指定なしの行は自動展開される

### lex 構文

| 構文 | 説明 | 例 |
|------|------|-----|
| `"phrase"` | 完全一致フレーズ | `"connection pool"` |
| `-term` | 除外 | `-redis` |
| `-"phrase"` | フレーズ除外 | `-"old api"` |
| 前方一致 | 接頭辞マッチ | `perf` → "performance" |

2-5 語でフィラーワードを除いたものが最も効果的。

---

## 設定ファイル (qmd.yml)

設定ファイルのパス: `~/.config/qmd/{indexName}.yml` (デフォルトの indexName は `index`)。
`--index` オプションで名前付きインデックスを使い分け可能。
`XDG_CONFIG_HOME` および `QMD_CONFIG_DIR` 環境変数で場所を変更できる。

### 完全スキーマ

```yaml
# グローバルコンテキスト (全コレクションに適用)
global_context: "[[WikiWord]] を見つけたら、そのワードで検索してください"

# エディタ URI テンプレート
editor_uri: "vscode://file/{path}:{line}"

# モデル上書き (オプション)
models:
  embed: "hf:Qwen/Qwen3-Embedding-0.6B-GGUF/Qwen3-Embedding-0.6B-Q8_0.gguf"
  rerank: "hf:giladgd/Qwen3-Reranker-4B-GGUF:Q8_0"
  generate: "hf:custom/generator.gguf"

# コレクション定義
collections:
  meetings:
    path: ~/Documents/Meetings        # 必須: インデックス対象ディレクトリ
    pattern: "**/*.md"                 # 必須: glob パターン (デフォルト: "**/*.md")
    ignore:                            # オプション: 除外 glob パターン
      - "Sessions/**"
      - "drafts/**"
    context:                           # オプション: パスプレフィックス → 説明
      "/": "ミーティングノートと議事録"
      "/2024": "2024年のミーティング"
    update: "git pull"                 # オプション: qmd update 時に実行するコマンド
    includeByDefault: true             # オプション: デフォルトで検索対象に含めるか (デフォルト: true)
```

### フィールド一覧

| フィールド | 型 | 必須 | 説明 |
|-----------|-----|------|------|
| `global_context` | string | — | 全コレクションに適用されるコンテキスト |
| `editor_uri` | string | — | エディタリンクテンプレート |
| `models.embed` | string | — | 埋め込みモデル URI |
| `models.rerank` | string | — | リランキングモデル URI |
| `models.generate` | string | — | クエリ展開モデル URI |
| `collections` | object | — | コレクション名 → 設定のマッピング |
| `collections.<name>.path` | string | 必須 | インデックス対象ディレクトリの絶対パス |
| `collections.<name>.pattern` | string | 必須 | glob パターン (デフォルト: `**/*.md`) |
| `collections.<name>.ignore` | string[] | — | 除外 glob パターン |
| `collections.<name>.context` | object | — | パスプレフィックス → 説明文のマッピング |
| `collections.<name>.update` | string | — | `qmd update` 時に実行する bash コマンド |
| `collections.<name>.includeByDefault` | boolean | — | デフォルト検索対象に含めるか (デフォルト: true) |

### コンテキストのマッチング

最長パスプレフィックスマッチで適用される。例: `journals` コレクション内の `/journal/2024/03/15.md` に対して:
- `/journal/2024` → "2024年のデイリーノート" (マッチ)
- `/` → "ノート Vault" (フォールバック)

該当なしの場合は `global_context` が使用される。

### コレクション名の制約

`^[a-zA-Z0-9_-]+$` (英数字、ハイフン、アンダースコアのみ)

---

## MCP サーバー

qmd は [Model Context Protocol](https://modelcontextprotocol.io/) サーバーとして動作し、AI アシスタントにローカル検索機能を提供する。

### 起動

```bash
# stdio 転送 (Claude Desktop / Claude Code 向け)
qmd mcp

# HTTP 転送 (共有サーバー)
qmd mcp --http                    # localhost:8181
qmd mcp --http --port 8080        # ポート指定
qmd mcp --http --daemon           # バックグラウンド (PID → ~/.cache/qmd/mcp.pid)
qmd mcp stop                      # デーモン停止
```

### Claude Desktop での設定

`~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "qmd": {
      "command": "qmd",
      "args": ["mcp"]
    }
  }
}
```

### Claude Code での設定

```bash
# マーケットプレースからインストール (推奨)
claude plugin marketplace add tobi/qmd
claude plugin install qmd@qmd
```

手動設定 (`~/.claude/settings.json`):

```json
{
  "mcpServers": {
    "qmd": {
      "command": "qmd",
      "args": ["mcp"]
    }
  }
}
```

### MCP ツール一覧

| ツール | 説明 |
|--------|------|
| `query` | 型付きサブクエリ (lex/vec/hyde) + RRF + リランキング |
| `get` | パス/docid でドキュメント取得 (ファジーマッチング対応) |
| `multi_get` | glob/CSV/docid による一括取得 |
| `status` | インデックス健全性とコレクション情報 |

### HTTP エンドポイント

| エンドポイント | 説明 |
|--------------|------|
| `POST /mcp` | MCP Streamable HTTP (JSON, ステートレス) |
| `GET /health` | ヘルスチェック + 稼働時間 |

モデルは VRAM に常駐し、5 分間アイドル後に自動解放 (再生成は ~1 秒)。

---

## データ保存パス

| パス | 内容 |
|------|------|
| `~/.cache/qmd/index.sqlite` | インデックスデータベース |
| `~/.cache/qmd/models/` | GGUF モデルキャッシュ |
| `~/.cache/qmd/mcp.pid` | MCP デーモン PID ファイル |
| `~/.config/qmd/qmd.yml` | 設定ファイル (オプション) |

---

## このリポジトリでの設定

### インストール

- **SSOT**: `nix/packages/all.nix` の `pnpmGlobal` リスト
- **Windows**: PnpmHandler が `windows/pnpm/packages.json` からインストール
- **Linux/macOS**: chezmoi `run_onchange_install-pnpm-global.sh.tmpl` が `pnpm add -g` でインストール

### モデル構成 (8GB VRAM)

シェル設定 (`zshrc`, `bashrc`, `PowerShell_profile.ps1`) で以下を設定:

```bash
export QMD_EMBED_MODEL="hf:Qwen/Qwen3-Embedding-0.6B-GGUF/Qwen3-Embedding-0.6B-Q8_0.gguf"
export QMD_RERANK_MODEL="hf:giladgd/Qwen3-Reranker-4B-GGUF:Q8_0"
```

| スロット | モデル | VRAM | 選定理由 |
|---------|--------|------|---------|
| Embedding | Qwen3-Embedding-0.6B | ~0.7GB | 日本語対応 (119 言語), MTEB 上位 |
| Reranker | Qwen3-Reranker-4B | ~4GB | giladgd (node-llama-cpp 作者) 版 GGUF で信頼性確保 |
| Generation | qmd-query-expansion-1.7B | ~1.1GB | 専用ファインチューニング (変更不可) |
| **合計** | | **~5.8GB** | |

**注意**:
- 埋め込みモデル変更後は `qmd embed -f` で再インデックスが必須
- Reranker GGUF はコミュニティ変換版に `cls.output.weight` 欠落の既知問題があるため、giladgd 版を使用

### 関連ファイル

| ファイル | 役割 |
|---------|------|
| `nix/packages/all.nix` | パッケージ SSOT (`pnpmGlobal`) |
| `chezmoi/.chezmoidata/pnpm_global.yaml` | chezmoi テンプレートデータ |
| `chezmoi/.chezmoiscripts/run_onchange_install-pnpm-global.sh.tmpl` | Linux/macOS インストールスクリプト |
| `chezmoi/shells/zshrc` | 環境変数設定 (Linux) |
| `chezmoi/shells/bashrc` | 環境変数設定 (Linux) |
| `chezmoi/shells/Microsoft.PowerShell_profile.ps1` | 環境変数設定 (Windows) |
