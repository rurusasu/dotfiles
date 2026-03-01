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

### 4. .env の作成

```powershell
Copy-Item .env.example .env
# OPENCLAW_UID / OPENCLAW_GID はデフォルト 1000 のまま（WSL2 デフォルト）
```

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

| ボリューム            | マウント先                          | 用途                                     |
| --------------------- | ----------------------------------- | ---------------------------------------- |
| `openclaw-data`       | `/app/data`                         | ワークスペース・ログ・スキル             |
| `openclaw-home`       | `/home/bun/.openclaw`               | canvas・cron など実行時ステート          |
| `.env` の設定ファイル | `/home/bun/.openclaw/openclaw.json` | 読み取り専用設定（home volume に重ねる） |

## 操作

```bash
# ログ確認
docker compose logs -f openclaw

# 再起動（設定変更後）
chezmoi apply && docker compose restart openclaw

# 完全再ビルド（openclaw バージョン更新時）
docker compose build --no-cache && docker compose up -d --force-recreate
```

## トラブルシューティング

```bash
# openclaw のヘルプ確認
docker compose run --rm openclaw --help

# コンテナ内の設定確認
docker compose exec openclaw cat /home/bun/.openclaw/openclaw.json

# ボリュームリセット（ワークスペースも消えるので注意）
docker compose down -v && docker compose up -d
```
