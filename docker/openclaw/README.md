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

**Personal ボルト / `TelegramBot` アイテム（認証情報 / Login）**

| フィールド | 内容                                                                              |
| ---------- | --------------------------------------------------------------------------------- |
| パスワード | BotFather から取得したボットトークン（例: `123456:ABCdef...`）                    |
| ユーザ名   | 自分の Telegram 数値ユーザーID（[@userinfobot](https://t.me/userinfobot) で確認） |

## 初回セットアップ

### 1. 確認事項

- `TelegramBot` アイテムにボットトークンと数値ユーザーIDが登録済みであることを確認

### 2. 設定ファイルのレンダリング

chezmoi が 1Password からシークレットを取得して設定ファイルを生成：

```bash
chezmoi apply
```

`~/.openclaw/openclaw.docker.json` が生成されることを確認：

```bash
cat ~/.openclaw/openclaw.docker.json
```

### 3. .env の作成

```bash
cp .env.example .env
# OPENCLAW_UID / OPENCLAW_GID を自分の UID/GID に合わせて編集（id コマンドで確認）
```

### 4. ビルド & 起動

```bash
docker compose build --no-cache
docker compose up -d
docker compose logs -f openclaw
```

Telegram でボットに DM を送ると応答が返れば成功。

## 設定ファイルの構成

| ファイル                                         | 用途                                        |
| ------------------------------------------------ | ------------------------------------------- |
| `chezmoi/dot_openclaw/openclaw.json.tmpl`        | ネイティブ（Windows 直接実行）用設定        |
| `chezmoi/dot_openclaw/openclaw.docker.json.tmpl` | **Docker 用設定**（このディレクトリで使用） |

Docker 用設定の特徴：

- ワークスペース: `/app/data/workspace`（名前付きボリューム内）
- Telegram チャンネル: `dmPolicy = allowlist`（1Password に登録したユーザーのみ）
- スキルの実行時インストール先: `/app/data/.bun`（ボリューム内）

## ボリューム

| ボリューム            | マウント先                          | 用途                         |
| --------------------- | ----------------------------------- | ---------------------------- |
| `openclaw-data`       | `/app/data`                         | ワークスペース・ログ・スキル |
| `.env` の設定ファイル | `/home/bun/.openclaw/openclaw.json` | 読み取り専用設定             |

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
