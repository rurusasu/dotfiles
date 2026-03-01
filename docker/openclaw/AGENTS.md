# docker/openclaw

Purpose: Docker コンテナで openclaw (Telegram AI ゲートウェイ) を実行する構成。

## ファイル構成

| ファイル             | 説明                                             |
| -------------------- | ------------------------------------------------ |
| `Dockerfile`         | Bun ベースイメージ + openclaw グローバル Install |
| `docker-compose.yml` | コンテナ定義（セキュリティ設定・ボリューム）     |
| `.env`               | 環境変数（gitignore済み・Handler が自動生成）    |
| `.env.example`       | .env のテンプレート                              |
| `.dockerignore`      | イメージに含めないファイルの除外設定             |

## 設定フロー

```
1Password (シークレット)
    ↓ onepasswordRead()
chezmoi/dot_openclaw/openclaw.docker.json.tmpl
    ↓ chezmoi apply
~/.openclaw/openclaw.docker.json   ← 1Password から値が展開済み
    ↓ read-only マウント
Docker コンテナ内 /home/bun/.openclaw/openclaw.json
```

Handler.OpenClaw.ps1 が以下を担う:

1. `chezmoi apply` で config ファイルを生成
2. `.env` を自動生成（`OPENCLAW_CONFIG_FILE` 等）
3. `docker compose up -d --build` でコンテナ起動

## セキュリティ設定

```yaml
read_only: true # コンテナ fs は読み取り専用
tmpfs:
  - /tmp:size=64m # /tmp のみ書き込み可
cap_drop: [ALL] # Linux ケーパビリティ全削除
security_opt:
  - no-new-privileges:true
pids_limit: 256
mem_limit: 512m
user: "1000:1000" # 非 root 実行
```

## ボリューム

| ボリューム         | コンテナ内パス                      | 用途                      |
| ------------------ | ----------------------------------- | ------------------------- |
| `openclaw-home`    | `/home/bun/.openclaw`               | canvas / cron 等の状態    |
| `openclaw-data`    | `/app/data`                         | workspace / skills / .bun |
| config file (bind) | `/home/bun/.openclaw/openclaw.json` | chezmoi 生成の設定 (ro)   |

## GitHub 認証

コンテナ内で git / gh CLI を使う場合は **Fine-grained PAT** を推奨。

### 方針

- Classic PAT ではなく **Fine-grained PAT** を使用（リポジトリ単位で権限を限定）
- 必要な権限のみ付与（Contents: Read / Metadata: Read 程度）
- 有効期限を設定（最大 90 日）
- 1Password に保存し、`.env` 経由でコンテナに渡す

### 1Password での保存先

```
op://Personal/GitHub/openclaw-token
```

### .env への追加項目（未実装・TODO）

```dotenv
GITHUB_TOKEN=<1Password から取得>
```

### docker-compose.yml への追加（未実装・TODO）

```yaml
environment:
  GITHUB_TOKEN: ${GITHUB_TOKEN:-}
```

### git config（Dockerfile または起動スクリプト・未実装・TODO）

```dockerfile
RUN git config --global url."https://x-access-token:${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"
```

> 実装時は Handler.OpenClaw.ps1 の `.env` 生成ブロックに
> `op read op://Personal/GitHub/openclaw-token` を追加する。

## 運用コマンド

```powershell
# 起動（Handler 経由・推奨）
pwsh -File scripts/powershell/install.user.ps1

# 手動操作
docker compose -f docker/openclaw/docker-compose.yml up -d --build
docker compose -f docker/openclaw/docker-compose.yml down
docker compose -f docker/openclaw/docker-compose.yml logs -f

# コンテナ内確認
docker exec -it openclaw sh
```

## 設定ファイルの更新

```powershell
# 1Password の値が変わった場合
chezmoi apply   # openclaw.docker.json を再生成
docker restart openclaw
```
