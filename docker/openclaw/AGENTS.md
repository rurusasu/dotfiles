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

コンテナ内で git を使う場合は **Fine-grained PAT** を使用。

### 方針

- Classic PAT ではなく **Fine-grained PAT** を使用（リポジトリ単位で権限を限定）
- 必要な権限のみ付与（Contents: Read / Metadata: Read 程度）
- 有効期限を設定（最大 90 日）
- 1Password に保存し、`.env` 経由でコンテナに渡す

### 1Password での保存先

```
op://Personal/GitHub/pat-used-openclaw
```

### 仕組み

```
1Password (op://Personal/GitHub/pat-used-openclaw)
    ↓ op read（Handler.OpenClaw.ps1 が自動取得）
.env: GITHUB_TOKEN=<PAT>
    ↓ docker-compose.yml で環境変数として渡す
コンテナ内 GITHUB_TOKEN + GIT_ASKPASS=/usr/local/bin/git-credential-askpass.sh
    ↓ git が HTTPS 認証時に呼び出す
PAT をパスワードとして使用
```

### 実装内容

**Dockerfile**:

- `git` + `openssh-client` をインストール
- `GIT_ASKPASS` ヘルパースクリプト（`/usr/local/bin/git-credential-askpass.sh`）を追加
  - `${GITHUB_TOKEN}` はビルド時ではなく**実行時**に評価される
- `USER bun` 後に git global config を設定（`safe.directory "*"` 含む）

**docker-compose.yml**:

```yaml
environment:
  GITHUB_TOKEN: ${GITHUB_TOKEN:-}
  GIT_ASKPASS: /usr/local/bin/git-credential-askpass.sh
```

**Handler.OpenClaw.ps1** の `EnsureEnvFile`:

- `op` CLI が利用可能かつサインイン済みの場合、自動的に PAT を取得して `.env` に書き込む
- `op` 未インストール・サインアウト時は `GITHUB_TOKEN=`（空文字）として生成

### 初回セットアップ

1. GitHub で Fine-grained PAT を作成（Contents: Read, Metadata: Read）
2. 1Password に `op://Personal/GitHub/pat-used-openclaw` として保存
3. `op signin` でサインイン後、Handler を実行すると `.env` に自動反映

### 既存の .env がある場合

`EnsureEnvFile` は `.env` が存在する場合スキップする。手動で追記するか `.env` を削除して再生成:

```powershell
Remove-Item docker\openclaw\.env
pwsh -File scripts\powershell\install.user.ps1
```

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
