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

`.env` には GitHub PAT を保存しない。PAT は起動時に `Handler.OpenClaw.ps1` が
1Password から取得し、Docker secret 経由でコンテナに注入する（環境変数には渡さない）。

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

| ボリューム                       | マウント先                          | 用途                                               |
| -------------------------------- | ----------------------------------- | -------------------------------------------------- |
| `openclaw-data`                  | `/app/data`                         | ワークスペース・ログ・スキル                       |
| `openclaw-home`                  | `/home/bun/.openclaw`               | canvas・cron など実行時ステート                    |
| `.env` の `OPENCLAW_CONFIG_FILE` | `/home/bun/.openclaw/openclaw.json` | 読み取り専用設定（home volume に重ねる）           |
| `gemini.settings.json`           | `/app/gemini.settings.json`         | Docker 用 Gemini 最小設定（イメージ内）            |
| `acpx.config.json`               | `/app/acpx.config.json`             | Gemini 実行コマンド上書き（ACP モード）            |
| Docker secret `github_token`     | `/run/secrets/github_token`         | GitHub PAT（Docker secret で注入、ディスク不使用） |

## 操作

```bash
# ログ確認
docker compose logs -f openclaw

# 再起動（設定変更後）
chezmoi apply && docker compose restart openclaw

# 完全再ビルド（openclaw バージョン更新時）
docker compose build --no-cache && docker compose up -d --force-recreate
```

Handler を使わず手動で起動する場合は、Docker secret 経由でトークンを注入する:

```powershell
$secretDir = "$env:USERPROFILE\.openclaw\secrets"
New-Item -ItemType Directory -Path $secretDir -Force | Out-Null
op read "op://Personal/GitHubUsedOpenClawPAT/credential" | Set-Content -NoNewline "$secretDir\github_token"
$env:OPENCLAW_GITHUB_TOKEN_FILE = ($secretDir -replace '\\', '/') + '/github_token'
docker compose up -d --build
Remove-Item "$secretDir\github_token" -Force
Remove-Item Env:\OPENCLAW_GITHUB_TOKEN_FILE -ErrorAction SilentlyContinue
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
