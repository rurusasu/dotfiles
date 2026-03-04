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
1Password から取得し、`~/.openclaw/secrets/github_token` 経由で Docker secret として注入する。

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
- Telegram チャンネル: `dmPolicy = pairing`（初回メッセージ時にペアリングコードで承認）
- スキルの実行時インストール先: `/app/data/.bun`（ボリューム内）

## ボリューム

| ボリューム                       | マウント先                          | 用途                                                  |
| -------------------------------- | ----------------------------------- | ----------------------------------------------------- |
| `openclaw-data`                  | `/app/data`                         | ワークスペース・ログ・スキル                          |
| `openclaw-home`                  | `/home/bun/.openclaw`               | canvas・cron など実行時ステート                       |
| `.env` の `OPENCLAW_CONFIG_FILE` | `/home/bun/.openclaw/openclaw.json` | 読み取り専用設定（home volume に重ねる）              |
| `gemini.settings.json`           | `/app/gemini.settings.json`         | Docker 用 Gemini 最小設定（イメージ内）               |
| `acpx.config.json`               | `/app/acpx.config.json`             | Gemini 実行コマンド上書き（ACP モード）               |
| Docker secret `github_token`     | `/run/secrets/github_token`         | GitHub PAT（`~/.openclaw/secrets/github_token` 由来） |

## 操作

```bash
# ログ確認
docker compose logs -f openclaw

# 再起動（設定変更後）
chezmoi apply && docker compose restart openclaw

# 完全再ビルド（openclaw バージョン更新時）
docker compose build --no-cache && docker compose up -d --force-recreate
```

Handler を使わず手動で起動する場合は、`OPENCLAW_GITHUB_TOKEN_FILE` を事前に渡す:

```powershell
$tmp = New-TemporaryFile
op read "op://Personal/GitHubUsedOpenClawPAT/credential" | Set-Content -NoNewline $tmp
$env:OPENCLAW_GITHUB_TOKEN_FILE = ($tmp.FullName -replace '\\', '/')
docker compose up -d --build
Remove-Item $tmp -Force
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
`acpx gemini` が `gemini --experimental-acp` で起動するよう固定する。

設定変更後は再作成で反映:

```bash
docker compose up -d --build --force-recreate
```

`acpx --verbose --timeout 20 gemini exec "ping"` が
`initialize -> session/new` まで進んで `429 RESOURCE_EXHAUSTED` になる場合は、
ローカル設定ではなく Gemini 側の一時的な容量制限が原因。

### Subagents の完了判定を安定化する

`sessions_spawn` は非同期で `accepted` を返すため、announce だけで完了判定しない。

- 1. `sessions_spawn` 後に `runId` / `childSessionKey` を保持する
- 2. `sessions_history(childSessionKey)` または `/subagents info` で完了状態を確認する
- 3. announce はユーザー通知用途として扱う（機械判定の唯一ソースにしない）

このリポジトリの Docker 設定では、子セッション追跡を安定化するために
`openclaw.docker.json` 側で以下を明示する:

- `agents.defaults.subagents.maxSpawnDepth = 2`
- `agents.defaults.sandbox.sessionToolsVisibility = "all"`
- `tools.sessions.visibility = "all"`

Sources:

- https://docs.openclaw.ai/tools/subagents
- https://docs.openclaw.ai/concepts/session-tool
- https://docs.openclaw.ai/tools
- https://docs.openclaw.ai/session
