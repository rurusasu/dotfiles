# openclaw Docker: ビルド・デプロイの必須ルール

このディレクトリは、openclaw (Telegram / Slack AI gateway) を Docker で動かすためのビルド・デプロイ構成を管理する。
運用ルール（sandbox 制約、ACP 使い方、cognee-skills、トラブルシューティング等）は [openclaw-workspace](https://github.com/rurusasu/openclaw-workspace) リポジトリを参照。

## 変更時に必ず触るファイル

- `docker/openclaw/Dockerfile`
- `docker/openclaw/docker-compose.yml`
- `docker/openclaw/entrypoint.sh`
- `docker/openclaw/config/acpx.config.json`
- `docker/openclaw/config/gemini.settings.json`
- `docker/openclaw/.env`（通常は自動生成。手動編集は最小限）
- `chezmoi/dot_openclaw/openclaw.docker.json.tmpl`（設定の source of truth）
- `docker/openclaw/apps/sandbox/` — sandbox サイドカーコンテナ

## 起動と再生成の正規フロー

`scripts/powershell/install.user.ps1` (Handler.OpenClaw.ps1) が以下を一括実行する。

1. `chezmoi apply` で設定を展開
2. `.env` を生成（`OPENCLAW_CONFIG_FILE` など。シークレットは含めない）
3. 1Password からシークレットを取得し、環境変数にセット（`OPENCLAW_GITHUB_TOKEN`, `OPENCLAW_XAI_API_KEY`）
4. `docker compose up -d --build` で起動（Docker Compose が環境変数から environment-based secret を生成し、コンテナ内 `/run/secrets/` に注入）

通常の起動・復旧はこのコマンドを使う。

```powershell
pwsh -File scripts/powershell/install.user.ps1
```

## 設定値の流れ

```text
1Password secret
  -> chezmoi template (dot_openclaw/openclaw.docker.json.tmpl)
  -> ~/.openclaw/openclaw.docker.json
  -> container: /home/app/.openclaw/openclaw.json (read-only bind)
```

1Password の値変更後は再展開してコンテナ再起動する。

```powershell
chezmoi apply
docker restart openclaw
```

## セキュリティ制約（設計前提）

### コンテナ硬化

`docker-compose.yml` は以下前提で維持する。

- `read_only: true`
- `tmpfs: /tmp`
- `cap_drop: [ALL]`
- `security_opt: no-new-privileges:true`
- `user: "1000:1000"`
- `pids_limit: 256`
- `mem_limit: 2g`
- `network_mode: host`（ペアリング自動承認のため loopback 接続が必要）
- `gateway.bind: "loopback"`（外部公開しない）

ビルトイン sandbox コンテナは OpenClaw が Docker Engine 経由で自動生成するため、
上記の hardened ルールは Gateway コンテナ自体に適用される。

### チャンネルアクセス制御

- Telegram: `dmPolicy: "allowlist"` + `allowFrom` でユーザー ID を限定
- Slack DM: `dmPolicy: "allowlist"` + `allowFrom` でユーザー ID を限定
- Slack チャンネル: `groupPolicy: "allowlist"` + `channels` で許可チャンネル ID を明示指定、`requireMention: true`
- Slack ユーザー ID は 1Password に保存（アカウント特定に使えるため）
- Slack チャンネル ID はテンプレートにべた書きで可（URL に含まれる公開情報であり秘匿不要）

### Slack チャンネルごとの専用エージェント（1エージェント = 1チャンネル）

各 Slack チャンネルに専用エージェント（ACP 経由 Claude Code）を割り当て、コンテキストの混入を防止する。
チャンネル間でセッション・メモリ・ワークスペースが完全に分離される。

**設計判断:**

- チャンネルごとにエージェントを分離することで、異なるチャンネルの文脈が混ざらない（記事「1エージェント = 1用途」の設計思想）
- すべて ACP 経由（`claude-agent-acp`）で Claude Code を使用。Consumer ToS により Claude Max 認証を直接モデル指定で使うのは規約違反のため、ACP ランタイムが必須
- `bindings` の `peer.kind: "channel"` + `peer.id` でチャンネル ID ベースのルーティング
- binding にマッチしない Slack DM や Telegram は `main`（default）エージェントにフォールバック

**設定の管理:**

- チャンネルリストは `chezmoi/.chezmoidata/openclaw.yaml` の `slackAgents` で一元管理
- テンプレート（`openclaw.docker.json.tmpl`）は `range` ループで `agents.list`、`bindings`、`channels.slack.channels` を自動生成
- チャンネルの追加・削除は `openclaw.yaml` の `slackAgents` リストを編集するだけでよい

### Gateway

- `gateway.mode: "local"` + `gateway.bind: "loopback"` + `gateway.auth.mode: "token"` で保護
- gateway token は 1Password から取得

## 必須ボリューム

- `openclaw-home` -> `/home/app/.openclaw`（openclaw state）
- `openclaw-acpx` -> `/home/app/.acpx`（acpx runtime state）
- `openclaw-data` -> `/app/data`（workspace / skills）
- bind mount -> `/home/app/.openclaw/openclaw.json`（config read-only）
- bind mount -> `/home/app/.claude`（Claude Code OAuth 認証情報）
- bind mount -> `/home/app/.claude.json:ro`（Claude Code 設定ファイル）
- bind mount -> `/home/app/.gemini`（Gemini CLI OAuth 認証情報）
- `/var/run/docker.sock` -> `/var/run/docker.sock`（ビルトイン sandbox のコンテナ生成に必要）

## シークレット注入の実装ルール

すべての 1Password 由来シークレットは **Docker Compose file-based secrets** で注入する。
シークレットファイルは `~/.openclaw/secrets/` に永続化し、`.env` からパスを参照する。

### なぜ `file:` ベースか

Docker Compose の `environment:` ベース secrets は、`read_only: true` 環境では `docker cp` が拒否されるため **構造的に動作しない**。
`file:` ベースは bind mount で処理されるため動作する。これは Docker Engine API の制限。

参照:

- https://github.com/docker/compose/issues/12031
- https://github.com/docker/compose/issues/12303

### 設計方針

- **禁止**: `docker-compose.yml` の `environment` セクションにシークレットを直接書かないこと
- **禁止**: シークレットファイルを `finally` ブロックで削除しないこと
- **禁止**: `secrets.*.environment` を使わないこと（`read_only: true` と非互換）
- Handler が 1Password → `~/.openclaw/secrets/` → `.env` → `docker compose up` → `/run/secrets/` に注入
- `entrypoint.sh` が `/run/secrets/*` を読み取り、環境変数にセットする

### シークレット一覧

| 1Password 参照先                                 | `.env` 変数名                | コンテナ内                                   | 必須 |
| ------------------------------------------------ | ---------------------------- | -------------------------------------------- | ---- |
| `op://Personal/GitHubUsedOpenClawPAT/credential` | `OPENCLAW_GITHUB_TOKEN_FILE` | `/run/secrets/github_token` → `GITHUB_TOKEN` | Yes  |
| `op://Personal/xAI-Grok-Twitter/console/apikey`  | `OPENCLAW_XAI_API_KEY_FILE`  | `/run/secrets/xai_api_key` → `XAI_API_KEY`   | No   |

### Sandbox シークレットポリシー

sandbox コンテナに注入するシークレットはホワイトリスト方式で管理する。

**許可（sandbox env に渡すもの）:**

| キー                        | 用途                  | スコープ              |
| --------------------------- | --------------------- | --------------------- |
| `GITHUB_TOKEN` / `GH_TOKEN` | git clone, gh CLI     | repo read/write       |
| `XAI_API_KEY`               | Grok API（X投稿取得） | read-only（x_search） |

**拒否（絶対に sandbox に渡さないもの）:**
Telegram bot token, Slack bot/app token, Gateway auth token, 1Password サービスアカウントトークン

## Claude Code ACP 連携（ACPX 経由）

### 禁止: OpenClaw のメインモデルに Claude Max 認証を使用しないこと

Anthropic の Consumer ToS により、Claude Max の OAuth 認証は Claude Code と claude.ai 専用。
OpenClaw のメインモデルとして使うのは規約違反。Anthropic API Key（従量課金）または Bedrock/Vertex を使うこと。

### インストール要件

Dockerfile に以下 2 パッケージが必要:

- `@anthropic-ai/claude-code` — Claude Code CLI 本体
- `@zed-industries/claude-agent-acp` — ACP プロトコルアダプタ

`claude-agent-acp` は **必ず Dockerfile でグローバルインストール** する。
`read_only: true` + `cap_drop: ALL` 環境では `npx` による動的ダウンロードが動作しない。

### acpx.config.json

```json
{
  "agents": {
    "claude": {
      "command": "claude-agent-acp"
    }
  }
}
```

**注意**: `"command": "claude --dangerously-skip-permissions"` は不可。ACPX は ACP プロトコル（JSON-RPC）で通信するが、Claude Code CLI は ACP を直接サポートしない。

### ホスト側の認証情報マウント

| ホスト           | コンテナ                 | 内容                                                   |
| ---------------- | ------------------------ | ------------------------------------------------------ |
| `~/.claude/`     | `/home/app/.claude`      | `.credentials.json`（OAuth トークン）, `settings.json` |
| `~/.claude.json` | `/home/app/.claude.json` | プロファイル設定（HOME ルートに配置が必要）            |

### 動作確認コマンド

```bash
# Claude Code 単体テスト
docker exec openclaw claude --dangerously-skip-permissions -p "Reply exactly: pong" --output-format json

# ACPX 経由テスト
MSYS_NO_PATHCONV=1 docker exec openclaw acpx --verbose --timeout 180 claude exec "Reply exactly: pong"
```

### OpenClaw バージョン要件

OpenClaw 2026.3.2 以降を推奨（PTY 修正 PR #34020）。

## Superpowers（obra/superpowers）

`entrypoint.sh` が `/app/data/superpowers` に shallow clone し、各エージェントのスキル検出パスにシンボリックリンクで配線する。

新しい ACP エージェントに追加する手順:

1. スキル検出パスを確認
2. `entrypoint.sh` の `# --- Superpowers ---` セクションに `ln -sfn` を追加
3. read-only FS 上の場合、`docker-compose.yml` の tmpfs に追加
4. `tests/test-entrypoint.sh` にリンク先を追加

## スキル変更のコミット手順

コンテナ内でスキルを編集した場合、ホスト側で chezmoi re-add を実行してソースに同期する。

```text
コンテナ内編集 → /home/app/.claude/skills/ (bind mount) → ホスト ~/.claude/skills/ → chezmoi re-add → chezmoi/dot_claude/skills/ (Git)
```

```powershell
chezmoi re-add ~/.claude/skills/
```

## sandbox イメージのビルド

ホスト側で BuildKit を使ってビルドする（コンテナ内の legacy builder では ARG 評価の問題があるため）。

```bash
task sandbox:build
```

## 手動操作コマンド

```powershell
docker compose -f docker/openclaw/docker-compose.yml up -d --build
docker compose -f docker/openclaw/docker-compose.yml down
docker compose -f docker/openclaw/docker-compose.yml logs -f
docker exec -it openclaw sh
```

## Sandbox Workspace アクセスと永続化

### 背景: Windows + WSL + Docker 構成でのパスマッピング不一致

sandbox は Gateway の子コンテナではなく、Docker Engine から直接作成される **sibling コンテナ** である。
OpenClaw が `workspaceAccess: "rw"` で sandbox に渡す bind source はコンテナ内パスだが、
Docker Engine はこれを **ホスト上のパス** として解釈する。
named volume の実体はホスト上の別の場所にあるため、sandbox と gateway は同じ workspace を指さない。

経緯:

- `9e65a58`: `workspaceAccess: "rw"` に変更を試みた
- `24dcda1`: パスマッピング不一致により書き込みが反映されないことを確認、`"none"` に revert
- 参照: [Issue #31331](https://github.com/openclaw/openclaw/issues/31331), [PR #31457](https://github.com/openclaw/openclaw/pull/31457)

### 解決策: POSIX パスによる gateway workspace + workspaceAccess: "rw"

gateway の workspace パスを Docker Desktop が解決できる POSIX パス（`/c/Users/...`）に設定する。
`workspaceAccess: "rw"` で OpenClaw が sandbox に workspace を自動マウントする際、
このパスが Docker Engine にそのまま渡され、同じ物理ディレクトリを参照する。

```
Host:     C:/Users/rurus/openclaw-workspace          (実ファイル)
Gateway:  bind mount → /c/Users/rurus/...            (docker-compose.yml, OPENCLAW_WORKSPACE_POSIX)
Sandbox:  auto mount → /workspace:rw                 (workspaceAccess: "rw" が自動設定)
          source: /c/Users/rurus/openclaw-workspace   ← Docker Engine が Windows FS に解決
```

#### パス形式の使い分け（重要）

Docker Desktop WSL2 環境では、パス形式の選択が重要。

| 用途                                          | 変数名                     | パス形式         | 例                                  |
| --------------------------------------------- | -------------------------- | ---------------- | ----------------------------------- |
| docker-compose.yml bind source                | `OPENCLAW_WORKSPACE_DIR`   | Windows          | `C:/Users/rurus/openclaw-workspace` |
| gateway workspace + sandbox auto-mount source | `OPENCLAW_WORKSPACE_POSIX` | POSIX (`/c/...`) | `/c/Users/rurus/openclaw-workspace` |

**試行して失敗したパス形式:**

| 形式                          | 結果         | 理由                                                                     |
| ----------------------------- | ------------ | ------------------------------------------------------------------------ |
| `C:/Users/...`                | 拒否         | OpenClaw が `C:` をパスコンポーネントとして解釈（POSIX 非準拠）          |
| `/mnt/c/Users/...`            | 書き込み不達 | Docker VM 内に新ディレクトリが作られるだけで Windows FS にマップされない |
| `/run/desktop/mnt/host/c/...` | 拒否         | OpenClaw が `/run` をシステムディレクトリとしてブロック                  |
| `/c/Users/...`                | **成功**     | Docker Desktop が Windows FS に解決し、OpenClaw も POSIX パスとして受理  |

**試行して失敗したアプローチ:**

| アプローチ                                                          | 結果                      | 理由                                                           |
| ------------------------------------------------------------------- | ------------------------- | -------------------------------------------------------------- |
| `workspaceAccess: "none"` + 明示的 `binds` → `/workspace`           | Duplicate mount point     | OpenClaw が `"none"` でも `/workspace` に auto-mount する      |
| `workspaceAccess: "none"` + 明示的 `binds` → `/home/user/workspace` | Sandbox path is read-only | sandbox セキュリティが `/workspace` 以外への書き込みをブロック |

#### 変更したファイル

| ファイル                             | 変更内容                                                                    |
| ------------------------------------ | --------------------------------------------------------------------------- |
| `chezmoi/.chezmoidata/openclaw.yaml` | `openclaw.workspace.hostPath`（Windows用）と `sandboxPath`（POSIX用）を追加 |
| `docker-compose.yml`                 | `${OPENCLAW_WORKSPACE_DIR}:${OPENCLAW_WORKSPACE_POSIX}` bind mount を追加   |
| `openclaw.docker.json.tmpl`          | `workspace` を `sandboxPath` に変更、`workspaceAccess: "rw"` に設定         |
| `Handler.OpenClaw.ps1`               | `.env` に `OPENCLAW_WORKSPACE_DIR` と `OPENCLAW_WORKSPACE_POSIX` を生成     |
| `entrypoint.sh`                      | workspace パスを `OPENCLAW_WORKSPACE_POSIX` 環境変数から取得                |

#### sandbox 設定の説明

```jsonc
"workspace": "/c/Users/rurus/openclaw-workspace",  // POSIX パスで gateway workspace を指定
"workspaceAccess": "rw",                            // sandbox に workspace を read-write でマウント
// 明示的 binds は不要 — OpenClaw が workspace パスを sandbox に自動マウントする
```

OpenClaw が `workspaceAccess: "rw"` で sandbox を作成する際、gateway の workspace パス
（`/c/Users/rurus/openclaw-workspace`）を Docker Engine に bind source として渡す。
Docker Desktop は `/c/...` パスを Windows ファイルシステムに解決するため、
sandbox の `/workspace` とホストの `C:/Users/rurus/openclaw-workspace` が同じ物理ディレクトリを指す。

#### ワークスペースパスの変更

パスは `chezmoi/.chezmoidata/openclaw.yaml` で管理。2つの形式を設定する:

| 変数          | 用途                                                 | 例                                  |
| ------------- | ---------------------------------------------------- | ----------------------------------- |
| `hostPath`    | docker-compose.yml bind source（Windows パス）       | `C:/Users/rurus/openclaw-workspace` |
| `sandboxPath` | gateway workspace + sandbox auto-mount（POSIX パス） | `/c/Users/rurus/openclaw-workspace` |

### ツール実行場所の整理

| ツール                          | 実行場所                            | 対象                                                                         |
| ------------------------------- | ----------------------------------- | ---------------------------------------------------------------------------- |
| `memory_search` / `memory_get`  | **Gateway 側**（AgentRuntime 内）   | メモリの読み取り・検索（SQLite + QMD）                                       |
| `file_write` / `write` / `edit` | **Sandbox 内**                      | `/workspace/` に書く → **ホスト bind mount 経由で gateway workspace に反映** |
| メモリフラッシュ（自動）        | **Sandbox 内**（`file_write` 経由） | コンテキスト圧縮前に MEMORY.md / memory/ に自動保存                          |

**注意: メモリの書き込み専用ツールは存在しない。**
`memory_search` / `memory_get` は読み取り専用。メモリ書き込み（MEMORY.md, memory/YYYY-MM-DD.md）も
USER.md / SOUL.md の編集も、すべて `file_write` 経由で workspace に書く。
ホスト bind mount により、sandbox の `file_write` が gateway workspace に反映される。

### パスマッピングの既知バグ（修正済み）

過去に sandbox のパス検証で以下の問題が発生した。現在のバージョンでは修正済みだが、アップグレード時に再発しないか注意。

- [#9560](https://github.com/openclaw/openclaw/issues/9560): コンテナ内パス `/workspace/...` がホスト側パスと直接比較され "Path escapes sandbox root" エラー
- [#30582](https://github.com/openclaw/openclaw/issues/30582): `workspaceAccess: "rw"` でも `mkdirp` が境界チェックに失敗（2026.2.26 リグレッション、PR #30610 で修正）
- [#16790](https://github.com/openclaw/openclaw/issues/16790): システムプロンプトにホスト側パスが注入され、sandbox 内で使えない

## ビルトイン Cron ジョブ（定期タスク）

OpenClaw のビルトイン cron 機能でバックグラウンドタスクを定期実行する。
ジョブ定義は chezmoi テンプレートで管理し、Handler が初回起動時にコンテナへシードする。

### 設定ファイルの流れ

```text
chezmoi/dot_openclaw/cron/jobs.seed.json.tmpl   ← source of truth（テンプレート）
  → chezmoi apply
  → ~/.openclaw/cron/jobs.seed.json              ← ホスト上の展開済みファイル
  → Handler.OpenClaw.ps1 SeedCronJobs()
  → docker cp → /home/app/.openclaw/cron/jobs.json  ← コンテナ内（named volume）
  → OpenClaw Gateway が読み込み → cron 実行
```

### シード条件（重要）

Handler の `SeedCronJobs()` は以下の条件をすべて満たす場合のみシードをコピーする:

1. ホスト上に `~/.openclaw/cron/jobs.seed.json` が存在する（`chezmoi apply` 済み）
2. openclaw コンテナが起動中である
3. コンテナ内に `jobs.json` が存在しない

いずれかの条件を満たさない場合は Warning ログを出力してスキップする。

テンプレートを更新した後に反映するには:

```powershell
# 方法 1: コンテナ内の jobs.json を削除して Handler を再実行
docker exec openclaw rm /home/app/.openclaw/cron/jobs.json
pwsh -File scripts/powershell/install.user.ps1

# 方法 2: 手動コピー（PowerShell）
chezmoi apply
docker cp "$env:USERPROFILE/.openclaw/cron/jobs.seed.json" openclaw:/home/app/.openclaw/cron/jobs.json
docker restart openclaw
```

### 登録済みジョブ一覧

| ジョブ名                 | スケジュール            | 内容                                                                       |
| ------------------------ | ----------------------- | -------------------------------------------------------------------------- |
| `lifelog-daily-scaffold` | 毎日 23:55 JST          | lifelog の日次/週次/月次/年次テンプレートを生成                            |
| `lifelog-daily-git-sync` | 毎日 23:58 JST          | lifelog の変更を commit & push                                             |
| `workspace-git-sync`     | **10分ごと**（everyMs） | workspace を pull → git add → commit → push（pull-first）                  |
| `sandbox-gc`             | 毎時 0分 JST            | 終了済み sandbox コンテナ（`openclaw-sandbox-common:bookworm-slim`）を削除 |
| `cognee-daily-ingest`    | 毎日 23:50 JST          | セッション履歴を cognee に取り込み、スキルを自動改善                       |

### workspace-git-sync の詳細

`openclaw-workspace` リポジトリとローカルの双方向同期を10分間隔で実行する。

- lockfile（`.git/sync.lock`）で並行実行を防止
- `git pull --ff-only origin main` でリモートの変更を先に取り込み
- `git add -A` → 変更があれば `commit` → `push origin main`
- 失敗時は Telegram に通知、成功時は silent
- `sessionTarget: "isolated"` でメイン会話を汚さない

### ジョブの確認・手動実行

```bash
# 登録済みジョブ一覧
docker exec openclaw openclaw cron list

# 特定ジョブの即時実行
docker exec openclaw openclaw cron run <jobId>

# 実行履歴
docker exec openclaw openclaw cron runs --id <jobId> --limit 10
```

## ビルド時トラブルシューティング

- `acpx exited with code 1` → `openclaw-acpx` が `/home/app/.acpx` に mount され書き込み可能か確認
- `Invalid JSON in /home/app/.acpx/config.json` → `docker compose up -d --build --force-recreate` で再投入
- `acpx: not found` → `plugins.entries.acpx.config.command` を `/usr/local/bin/acpx` に固定
- `ENOENT` / `Permission denied` for `claude-agent-acp` → Dockerfile でグローバルインストールしているか確認
