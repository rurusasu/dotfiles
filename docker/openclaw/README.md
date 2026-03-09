# OpenClaw Docker

openclaw を Docker コンテナで動作させ、Telegram から即座に使える構成。

## 前提条件

- 1Password デスクトップアプリ（`op` CLI 経由でシークレットを取得）
- chezmoi（設定ファイルのレンダリング）
- Docker Desktop with WSL2 backend

## 1Password の準備

**Personal ボルト / `openclaw` アイテム（Login）**

| フィールド名    | 内容                                               |
| --------------- | -------------------------------------------------- |
| `gateway token` | openclaw Web UI アクセス用トークン（任意の文字列） |

**Personal ボルト / `TelegramBot` アイテム（API_CREDENTIAL タイプ）**

| フィールド | 内容                                                     |
| ---------- | -------------------------------------------------------- |
| `認証情報` | BotFather から取得したボットトークン（例: `123456:...`） |

**Personal ボルト / `SlackBot-OpenClaw` アイテム（API_CREDENTIAL タイプ）**

| フィールド        | 内容                                                |
| ----------------- | --------------------------------------------------- |
| `bot_token`       | Slack Bot User OAuth Token（`xoxb-...`）            |
| `app_level_token` | Slack App-Level Token（`xapp-...`、Socket Mode 用） |

**Personal ボルト / `Slack` アイテム（UUID: `22w7ub2pldlpo6tlmggc7g67mu`）**

| セクション / フィールド      | 内容                                           |
| ---------------------------- | ---------------------------------------------- |
| `Miki _Co` / `slack_user_id` | 自分の Slack ユーザー ID（`U` で始まる文字列） |

## 初回セットアップ

### 1. chezmoi.toml に 1Password CLI パスを追加

`~/.config/chezmoi/chezmoi.toml` に以下を追記（`op` が PATH にない場合）：

```toml
[onepassword]
    command = "C:/Users/<USERNAME>/AppData/Local/Microsoft/WinGet/Packages/AgileBits.1Password.CLI_Microsoft.Winget.Source_8wekyb3d8bbwe/op.exe"
```

> WinGet でインストールした 1Password CLI はデフォルトで PATH に追加されないため必要。

### 2. 確認事項

- `TelegramBot` アイテムの `認証情報` フィールドにボットトークンが登録済みであることを確認

### 3. 設定ファイルのレンダリング

chezmoi が 1Password からシークレットを取得して設定ファイルを生成：

```powershell
chezmoi apply "$env:USERPROFILE\.openclaw\openclaw.docker.json"
```

`~/.openclaw/openclaw.docker.json` が生成されることを確認：

```powershell
Get-Content "$env:USERPROFILE\.openclaw\openclaw.docker.json"
```

### 4. .env の作成（トークンは含めない）

```powershell
Copy-Item .env.example .env
# OPENCLAW_UID / OPENCLAW_GID はデフォルト 1000 のまま（WSL2 デフォルト）
```

`.env` にはシークレットを保存しない。シークレットは起動時に `Handler.OpenClaw.ps1` が
1Password から取得し、Docker Compose environment-based secret 経由でコンテナに注入する。

### 4. ビルド & 起動

```bash
docker compose build --no-cache
docker compose up -d
docker compose logs -f openclaw
```

Telegram でボットに DM を送るとペアリングコードが届くので承認すれば使用可能。

## 設定ファイルの構成

| ファイル                                         | 用途                                        |
| ------------------------------------------------ | ------------------------------------------- |
| `chezmoi/dot_openclaw/openclaw.json.tmpl`        | ネイティブ（Windows 直接実行）用設定        |
| `chezmoi/dot_openclaw/openclaw.docker.json.tmpl` | **Docker 用設定**（このディレクトリで使用） |

Docker 用設定の特徴：

- ワークスペース: `/app/data/workspace`（名前付きボリューム内）
- Telegram / Slack DM: `dmPolicy = allowlist`（許可ユーザーのみ応答）
- Slack チャンネル: `groupPolicy = allowlist`（許可チャンネルのみ、メンション必須）
- スキルの実行時インストール先: `/app/data/.bun`（ボリューム内）

## ボリューム

### openclaw コンテナ

| ボリューム                       | マウント先                          | 用途                                                         |
| -------------------------------- | ----------------------------------- | ------------------------------------------------------------ |
| `openclaw-data`                  | `/app/data`                         | ワークスペース・ログ・スキル                                 |
| `openclaw-home`                  | `/home/bun/.openclaw`               | canvas・cron など実行時ステート                              |
| `.env` の `OPENCLAW_CONFIG_FILE` | `/home/bun/.openclaw/openclaw.json` | 読み取り専用設定（home volume に重ねる）                     |
| `gemini.settings.json`           | `/app/gemini.settings.json`         | Docker 用 Gemini 最小設定（イメージ内）                      |
| `acpx.config.json`               | `/app/acpx.config.json`             | Gemini 実行コマンド上書き（ACP モード）                      |
| Docker secret `github_token`     | `/run/secrets/github_token`         | GitHub PAT（environment-based secret で注入）                |
| Docker secret `xai_api_key`      | `/run/secrets/xai_api_key`          | xAI API Key（environment-based secret で注入、オプショナル） |

### Docker socket

| マウント               | 用途                                             |
| ---------------------- | ------------------------------------------------ |
| `/var/run/docker.sock` | ビルトイン sandbox（sibling コンテナ生成に必要） |

## 操作

```bash
# ログ確認
docker compose logs -f openclaw

# 再起動（設定変更後）
chezmoi apply && docker compose restart openclaw

# 完全再ビルド（openclaw バージョン更新時）
docker compose build --no-cache && docker compose up -d --force-recreate
```

Handler を使わず手動で起動する場合は、シークレットファイルを書き出してから起動する:

```powershell
$secretDir = "$env:USERPROFILE\.openclaw\secrets"
New-Item -ItemType Directory -Path $secretDir -Force | Out-Null
op read "op://Personal/GitHubUsedOpenClawPAT/credential" | Set-Content -NoNewline "$secretDir\github_token"
op read "op://Personal/xAI-Grok-Twitter/console/apikey" | Set-Content -NoNewline "$secretDir\xai_api_key"
# .env に OPENCLAW_GITHUB_TOKEN_FILE / OPENCLAW_XAI_API_KEY_FILE が設定済みであることを確認
docker compose up -d --build
```

## トラブルシューティング

```bash
# openclaw のヘルプ確認
docker compose run --rm openclaw --help

# コンテナ内の設定確認
docker compose exec openclaw cat /home/bun/.openclaw/openclaw.json
docker compose exec openclaw cat /home/bun/.gemini/settings.json
docker compose exec openclaw cat /home/bun/.acpx/config.json

# ボリュームリセット（ワークスペースも消えるので注意）
docker compose down -v && docker compose up -d
```

### ACPX + Gemini が不安定なとき

`sessions_spawn(runtime:"acp")` がタイムアウトする場合、ホスト側 `~/.gemini/settings.json` の
`mcpServers` がコンテナ内で解決できず初期化遅延を起こすことがある。

この構成では起動時 entrypoint が `docker/openclaw/gemini.settings.json` を
`/home/bun/.gemini/settings.json` に上書きし、Docker 内では最小設定（`mcpServers: {}`）を使う。
認証情報は `GEMINI_CREDENTIALS_DIR` マウントから継続利用される。

さらに `docker/openclaw/acpx.config.json` を `/home/bun/.acpx/config.json` に投入し、
`acpx gemini` が `gemini --experimental-acp -m gemini-2.5-flash-lite` で起動するよう固定する。
`HOME` は `docker-compose.yml` の環境変数で `/home/bun` に固定し、認証ファイル参照先のぶれを防ぐ。

設定変更後は再作成で反映:

```bash
docker compose up -d --build --force-recreate
```

`acpx --verbose --timeout 120 gemini exec "ping"` が
`initialize -> session/new` まで進んで `429 RESOURCE_EXHAUSTED` になる場合は、
ローカル設定ではなく Gemini 側の一時的な容量制限が原因。

補足（2026-03-04 再テスト）:

- コンテナ内 `acpx --verbose --timeout 300 gemini exec "Reply exactly: pong"` は成功
- `sessions_spawn -> sessions_send` は成功しても、`sessions_send` の戻り payload に本文が入らないケースあり
- この場合でも gateway ログに `[agent:nested] ... pong` が出ていれば子実行自体は成功
- 既知事象として `sessions_history` 永続化/取得の不安定さが報告されている

### Subagents の完了判定を安定化する

`sessions_spawn` は非同期で `accepted` を返すため、announce だけで完了判定しない。

運用方針（推奨）:

- 子タスクは `sessions_spawn`（`runtime:"acp"` を付けない、`agentId:"main"`）による Codex 子を第一選択にする
- Gemini は Gemini 固有機能が必要な時だけ明示指定して使う

- 1. `sessions_spawn` 後に `runId` / `childSessionKey` を保持する
- 2. 子への実タスク送信は `sessions_send(timeoutSeconds>0)` で同期回収する（推奨）
- 3. `sessions_history(childSessionKey)` は補助用途に限定する（環境によって空のままになるケースあり）
- 4. announce はユーザー通知用途として扱う（機械判定の唯一ソースにしない）
- 5. `accepted` は実行成功ではないため、`timeout` / `failed` / `429` を明示判定する
- 6. `429 MODEL_CAPACITY_EXHAUSTED` は指数バックオフで再試行する

このリポジトリの Docker 設定では、子セッション追跡を安定化するために
`openclaw.docker.json` 側で以下を明示する:

- `agents.defaults.subagents.maxSpawnDepth = 2`
- `agents.defaults.sandbox.sessionToolsVisibility = "all"`
- `tools.sessions.visibility = "all"`
- `tools.agentToAgent.enabled = true`

運用上の既知事項:

- 一部環境では `sessions_history` が空を返すことがある（子実行自体は成功していても履歴取得できない）
- この場合は `sessions_send(timeoutSeconds)` の戻り本文を正として扱う
- `sessions_send` の payload 本文が空の場合は gateway ログの `[agent:nested]` を正として扱う

Sources:

- https://docs.openclaw.ai/tools/subagents
- https://docs.openclaw.ai/concepts/session-tool
- https://docs.openclaw.ai/tools
- https://docs.openclaw.ai/session
- https://github.com/openclaw/openclaw/issues/29593
- https://github.com/openclaw/openclaw/pull/32683

## ビルトイン Sandbox

OpenClaw のビルトイン sandbox 機能を使い、ツール実行（`shell_exec` 等）を隔離された
sibling Docker コンテナ内で実行する。

### 仕組み

```
openclaw (Gateway) ── Docker socket ──▶ Docker Engine
                                          │
                                     ┌────▼────────────────┐
                                     │ sandbox container    │
                                     │ (per session)        │
                                     │ network: none        │
                                     │ Python/Node/git/curl │
                                     └─────────────────────┘
```

- Gateway が Docker Engine API 経由で sandbox コンテナを自動生成・管理
- セッションごとに独立コンテナ（`scope: "session"`）
- セッション終了時に自動削除
- `docker ps` で確認可能

### パスマッピング

Gateway コンテナの `/app/data/workspace/` が sandbox 内では `/workspace/` にマウントされる。
sandbox 内のツール（`shell_exec`, `file_write` 等）では **`/workspace/` パスを使用すること**。
`/app/data/` パスは sandbox 内に存在しない。

| Gateway                        | sandbox               | 用途           |
| ------------------------------ | --------------------- | -------------- |
| `/app/data/workspace/`         | `/workspace/`         | ワークスペース |
| `/app/data/workspace/lifelog/` | `/workspace/lifelog/` | lifelog        |

### 設定

`openclaw.docker.json` の `agents.defaults.sandbox`:

```json
{
  "mode": "all",
  "scope": "session",
  "workspaceAccess": "rw",
  "docker": {
    "image": "openclaw-sandbox-common:bookworm-slim",
    "network": "none"
  }
}
```

| 設定              | 値                                      | 説明                                   |
| ----------------- | --------------------------------------- | -------------------------------------- |
| `mode`            | `"all"`                                 | 全セッションで sandbox を使用          |
| `scope`           | `"session"`                             | セッションごとに独立コンテナ           |
| `workspaceAccess` | `"rw"`                                  | ワークスペースを読み書き可能でマウント |
| `docker.image`    | `openclaw-sandbox-common:bookworm-slim` | Python 3, Node.js, git, curl, jq 入り  |
| `docker.network`  | `"none"`                                | ネットワークアクセスなし               |

### セキュリティ上の注意

Docker socket マウント（`/var/run/docker.sock`）は Gateway コンテナにホスト Docker への
アクセス権を与える。これは sandbox コンテナ生成に必須だが、理論上は任意のコンテナ操作が可能。
以下の対策で緩和する:

- `dmPolicy: "allowlist"` で信頼ユーザーのみに限定
- `groupPolicy: "allowlist"` + `requireMention: true` でチャンネルアクセスを限定
- Gateway 自体は `read_only: true` + `cap_drop: ALL` で hardened
- sandbox コンテナは `network: "none"`（外部通信不可）

### 動作確認

```bash
# sandbox 有効化の確認（設定ダンプ）
docker exec openclaw openclaw sandbox explain

# sandbox イメージの確認
docker exec openclaw docker images | grep sandbox

# 実行中の sandbox コンテナ一覧
docker ps --filter "ancestor=openclaw-sandbox-common:bookworm-slim"
```

### トラブルシューティング

- sandbox コンテナが起動しない
  - `docker exec openclaw docker info` で Docker socket アクセスを確認
  - WSL2 環境では Docker Desktop の設定で「Expose daemon on tcp://...」ではなく socket 経由を使う
- `openclaw-sandbox-common:bookworm-slim` イメージが見つからない
  - `docker exec openclaw openclaw sandbox build` で sandbox イメージをビルド
  - または `OPENCLAW_SANDBOX=1` 環境変数で起動時に自動ビルド
- sandbox 内でパッケージインストールが失敗
  - `docker.network: "none"` のためネットワークアクセス不可
  - 必要なパッケージは `docker.setupCommand` で事前インストールするか、カスタムイメージを使う
