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
- ポートは `127.0.0.1` にバインド（外部公開しない）

ビルトイン sandbox コンテナは OpenClaw が Docker Engine 経由で自動生成するため、
上記の hardened ルールは Gateway コンテナ自体に適用される。

### チャンネルアクセス制御

- Telegram: `dmPolicy: "allowlist"` + `allowFrom` でユーザー ID を限定
- Slack DM: `dmPolicy: "allowlist"` + `allowFrom` でユーザー ID を限定
- Slack チャンネル: `groupPolicy: "allowlist"` + `channels` で許可チャンネル ID を明示指定、`requireMention: true`
- Slack ユーザー ID は 1Password に保存（アカウント特定に使えるため）
- Slack チャンネル ID はテンプレートにべた書きで可（URL に含まれる公開情報であり秘匿不要）

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

## ビルド時トラブルシューティング

- `acpx exited with code 1` → `openclaw-acpx` が `/home/app/.acpx` に mount され書き込み可能か確認
- `Invalid JSON in /home/app/.acpx/config.json` → `docker compose up -d --build --force-recreate` で再投入
- `acpx: not found` → `plugins.entries.acpx.config.command` を `/usr/local/bin/acpx` に固定
- `ENOENT` / `Permission denied` for `claude-agent-acp` → Dockerfile でグローバルインストールしているか確認
