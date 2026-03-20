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

### 4. .env の作成

`Handler.OpenClaw.ps1` が初回起動時に `.env` を自動生成する。
手動で作成する場合は以下の変数を設定:

```env
OPENCLAW_PORT=18789
OPENCLAW_UID=1000
OPENCLAW_GID=1000
OPENCLAW_CONFIG_FILE=C:/Users/<USER>/.openclaw/openclaw.docker.json
TZ=Asia/Tokyo
GEMINI_CREDENTIALS_DIR=C:/Users/<USER>/.gemini
CLAUDE_CREDENTIALS_DIR=C:/Users/<USER>/.claude
CLAUDE_CONFIG_JSON=C:/Users/<USER>/.claude.json
OPENCLAW_WORKSPACE_DIR=C:/Users/<USER>/openclaw-workspace
OPENCLAW_GITHUB_TOKEN_FILE=C:/Users/<USER>/.openclaw/secrets/github_token
OPENCLAW_XAI_API_KEY_FILE=C:/Users/<USER>/.openclaw/secrets/xai_api_key
CODEX_AUTH_FILE=C:/Users/<USER>/.codex/auth.json
```

`.env` にはシークレットの値を直接書かない。シークレットは `Handler.OpenClaw.ps1` が
1Password から取得し、ファイルに書き出して Docker Compose file-based secret で注入する。

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

- ワークスペース: `/app/data/workspace`（ホスト bind mount、`OPENCLAW_WORKSPACE_DIR` で指定）
- Telegram / Slack DM: `dmPolicy = allowlist`（許可ユーザーのみ応答）
- Slack チャンネル: `groupPolicy = allowlist`（許可チャンネルのみ、メンション必須）
- スキルの実行時インストール先: `/app/data`（ボリューム内）

## ボリューム

### openclaw コンテナ

| ボリューム                       | マウント先                          | 用途                                                         |
| -------------------------------- | ----------------------------------- | ------------------------------------------------------------ |
| `openclaw-data`                  | `/app/data`                         | superpowers・lifelog・スキル                                 |
| `OPENCLAW_WORKSPACE_DIR`         | `/app/data/workspace`               | ワークスペース（ホスト bind mount、sandbox と共有）          |
| `openclaw-home`                  | `/home/app/.openclaw`               | canvas・cron など実行時ステート                              |
| `.env` の `OPENCLAW_CONFIG_FILE` | `/home/app/.openclaw/openclaw.json` | 読み取り専用設定（home volume に重ねる）                     |
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

## 外部スキルの追加

OpenClaw はスキル（`SKILL.md` を持つディレクトリ）を複数のソースから読み込む。
同名スキルは高優先度のソースが上書きする。

### スキル読み込み優先度（低→高）

| 優先度 | ソース          | パス                                   | 設定方法                                |
| ------ | --------------- | -------------------------------------- | --------------------------------------- |
| 1 (低) | `extraDirs`     | `skills.load.extraDirs` で任意パス指定 | `openclaw.docker.json`                  |
| 2      | bundled         | OpenClaw 同梱                          | 変更不可                                |
| 3      | managed         | `~/.openclaw/skills/`                  | `openclaw skills install <npm-package>` |
| 4      | personal agents | `~/.agents/skills/`                    | 手動配置 or シンボリックリンク          |
| 5      | project agents  | `<workspace>/.agents/skills/`          | 手動配置                                |
| 6 (高) | workspace       | `<workspace>/skills/`                  | 手動配置 or entrypoint でコピー         |

### スキルの最小構成

```
my-skill/
  SKILL.md
```

`SKILL.md` に YAML frontmatter が必要:

```markdown
---
name: my-skill
description: Use when ... （エージェントがスキルを選択する判断材料になる）
---

スキルの本文（エージェントが読み込んで従う指示）
```

オプションの frontmatter:

- `user-invocable: false` — `/my_skill` スラッシュコマンドを無効化
- `disable-model-invocation: true` — エージェントの `available_skills` に表示しない
- `metadata.openclaw.requires.bins: ["curl"]` — 必須バイナリ（なければスキップ）
- `metadata.openclaw.requires.env: ["API_KEY"]` — 必須環境変数
- `metadata.openclaw.always: true` — 要件チェックをバイパス

### 外部リポジトリをスキルとして追加する手順

#### 方法 A: `extraDirs` に追加（推奨）

1. `entrypoint.sh` でリポジトリを clone:

```sh
_custom_dir="/app/data/my-custom-skills"
_custom_repo="https://github.com/user/repo.git"
if [ ! -d "$_custom_dir/.git" ]; then
  git clone --depth 1 --single-branch "$_custom_repo" "$_custom_dir" 2>&1
else
  git -C "$_custom_dir" pull --ff-only 2>&1 || true
fi
```

2. `openclaw.docker.json.tmpl` の `skills.load.extraDirs` に追加:

```json
"skills": {
  "load": {
    "extraDirs": [
      "/app/data/superpowers/skills",
      "/app/data/my-custom-skills/skills"
    ]
  }
}
```

3. **sandbox からもスキルを参照可能にする** — extraDirs のスキルは Gateway がセッション開始時に sandbox ワークスペースへ自動同期するため、追加作業は不要。

#### 方法 B: workspace に直接コピー（最高優先度）

`entrypoint.sh` で `<workspace>/skills/` にコピー:

```sh
mkdir -p "$workspace_dir/skills/my-skill"
cp -rLf "/app/data/my-repo/skills/." "$workspace_dir/skills/my-skill/"
```

**注意**: シンボリックリンクではなく `cp -rL`（実体コピー）を使うこと。sandbox コンテナは `/app/data/workspace/` のみマウントするため、リンク先が `/app/data/workspace/` 外にあると sandbox 内で参照できない。

#### 方法 C: npm パッケージとしてインストール

```bash
docker exec openclaw openclaw skills install <package-name>
```

`~/.openclaw/skills/` にインストールされる（優先度 3）。

### スキルスナップショットの注意点

OpenClaw はセッションごとにスキル一覧のスナップショットをキャッシュする（`sessions.json` の `skillsSnapshot`）。**新しいスキルを追加してもコンテナ再起動だけでは既存セッションに反映されない。**

`entrypoint.sh` に以下のスナップショット無効化ステップが組み込まれている:

```sh
# sessions.json から skillsSnapshot を削除し、次のメッセージで再構築を強制
find "$_sessions_dir" -name "sessions.json" -type f | while read -r _sf; do
  node -e "..." # skillsSnapshot を削除
done
```

手動で無効化する場合:

```bash
docker exec openclaw node -e "
  const fs = require('fs');
  const p = '/home/app/.openclaw/agents/main/sessions/sessions.json';
  const d = JSON.parse(fs.readFileSync(p,'utf-8'));
  for (const k of Object.keys(d)) delete d[k].skillsSnapshot;
  fs.writeFileSync(p, JSON.stringify(d, null, 2));
"
```

### 動作確認

```bash
# Gateway レベルのスキル一覧（全ソース統合）
docker exec openclaw openclaw skills list

# スキルの詳細チェック（eligible / missing 分類）
docker exec openclaw openclaw skills check

# エージェントセッションで実際に見えるか確認
docker exec openclaw sh -c 'openclaw agent --agent main --message "Count all skills in available_skills" --json'
```

## トラブルシューティング

```bash
# openclaw のヘルプ確認
docker compose run --rm openclaw --help

# コンテナ内の設定確認
docker compose exec openclaw cat /home/app/.openclaw/openclaw.json
docker compose exec openclaw cat /home/app/.gemini/settings.json
docker compose exec openclaw cat /home/app/.acpx/config.json

# ボリュームリセット（ワークスペースはホスト bind mount なので消えない）
docker compose down -v && docker compose up -d
```

### ACPX + Gemini が不安定なとき

`sessions_spawn(runtime:"acp")` がタイムアウトする場合、ホスト側 `~/.gemini/settings.json` の
`mcpServers` がコンテナ内で解決できず初期化遅延を起こすことがある。

この構成では起動時 entrypoint が `docker/openclaw/gemini.settings.json` を
`/home/app/.gemini/settings.json` に上書きし、Docker 内では最小設定（`mcpServers: {}`）を使う。
認証情報は `GEMINI_CREDENTIALS_DIR` マウントから継続利用される。

さらに `docker/openclaw/acpx.config.json` を `/home/app/.acpx/config.json` に投入し、
`acpx gemini` が `gemini --experimental-acp -m gemini-2.5-flash-lite` で起動するよう固定する。
`HOME` は `docker-compose.yml` の環境変数で `/home/app` に固定し、認証ファイル参照先のぶれを防ぐ。

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
                                     │ network: bridge       │
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
  "workspaceAccess": "none",
  "docker": {
    "image": "openclaw-sandbox-common:bookworm-slim",
    "network": "bridge"
  }
}
```

| 設定              | 値                                      | 説明                                                               |
| ----------------- | --------------------------------------- | ------------------------------------------------------------------ |
| `mode`            | `"all"`                                 | 全セッションで sandbox を使用                                      |
| `scope`           | `"session"`                             | セッションごとに独立コンテナ                                       |
| `workspaceAccess` | `"none"`                                | sandbox は独立ワークスペースを使用（スキル・AGENTS.md は自動同期） |
| `docker.image`    | `openclaw-sandbox-common:bookworm-slim` | Python 3, Node.js, git, curl, jq 入り                              |
| `docker.network`  | `"bridge"`                              | 外部通信可能（pnpm install, Playwright E2E, API 呼び出し等に必要） |

### セキュリティ上の注意

Docker socket マウント（`/var/run/docker.sock`）は Gateway コンテナにホスト Docker への
アクセス権を与える。これは sandbox コンテナ生成に必須だが、理論上は任意のコンテナ操作が可能。
以下の対策で緩和する:

- `dmPolicy: "allowlist"` で信頼ユーザーのみに限定
- `groupPolicy: "allowlist"` + `requireMention: true` でチャンネルアクセスを限定
- Gateway 自体は `read_only: true` + `cap_drop: ALL` で hardened
- sandbox コンテナは `network: "bridge"`（外部通信可能 — Playwright E2E、API 呼び出し等に必要）

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
  - `docker.network: "bridge"` でも DNS 障害時にはインストール失敗する
  - sandbox イメージにプリインストールされていないパッケージは `docker.setupCommand` で事前インストールするか、カスタムイメージを使う
