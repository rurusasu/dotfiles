# OpenClaw Kind Migration Design

## 概要

OpenClaw の構築・設定・デプロイを dotfiles リポジトリから完全に分離し、Kind (Kubernetes in Docker) で管理する新リポジトリ `openclaw-k8s` に移行する。

## 動機

- Docker Compose の制約（シークレット管理、ヘルスチェック、設定注入、マルチコンテナ管理）が運用の複雑さの主因
- chezmoi テンプレート → .env → docker-compose → entrypoint.sh の多段変換パイプラインを解消
- OpenClaw 関連の変更が dotfiles の大半を占めており、関心の分離が必要

## 技術選定

| 項目                 | 選定                                          | 理由                                                         |
| -------------------- | --------------------------------------------- | ------------------------------------------------------------ |
| オーケストレーション | Kind + Kustomize                              | シンプル、透明、クラウド K8s への overlay 追加で移行可能     |
| シークレット管理     | 1Password Connect + External Secrets Operator | 既存 1Password 運用を活かし、多段パイプラインを 3 段に簡素化 |
| sandbox              | 現行維持（Docker socket マウント）            | OpenClaw ビルトイン sandbox を変更なしで利用                 |
| タスクランナー       | Taskfile                                      | クロスプラットフォーム、PowerShell 依存を排除                |
| cron                 | OpenClaw ビルトイン（ConfigMap 注入）         | エージェントセッション・メモリ統合を維持                     |

## リポジトリ構造

```
openclaw-k8s/
├── CLAUDE.md
├── Taskfile.yml
├── kind/
│   └── cluster.yaml             # Kind クラスタ定義
├── docker/
│   ├── gateway/
│   │   ├── Dockerfile
│   │   ├── entrypoint.sh        # 簡素化版（~250行、シークレット注入削除）
│   │   └── .dockerignore
│   └── sandbox/
│       └── Dockerfile.custom
├── base/
│   ├── kustomization.yaml
│   ├── namespace.yaml           # namespace: openclaw
│   ├── gateway/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── configmap.yaml       # openclaw.json
│   ├── cognee-skills/
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   ├── secrets/
│   │   ├── secretstore.yaml     # 1Password Connect 接続定義
│   │   └── externalsecrets.yaml # シークレット同期定義
│   └── cron/
│       └── configmap.yaml       # jobs.json
├── overlays/
│   └── local/
│       ├── kustomization.yaml
│       └── patches/
├── docs/
│   ├── architecture.md
│   ├── setup.md
│   └── migration-from-dotfiles.md
└── tests/
    └── test-entrypoint.sh
```

## Kind クラスタ定義

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 30789
        hostPort: 41789 # Gateway API
        protocol: TCP
      - containerPort: 30791
        hostPort: 41791 # Control UI
        protocol: TCP
    extraMounts:
      - hostPath: /var/run/docker.sock
        containerPath: /var/run/docker.sock
      - hostPath: C:/Users/rurus/openclaw-workspace
        containerPath: /workspace
```

## シークレット管理

### 現行フロー（6 段）

```
1Password → op read → ファイル書き出し → .env → docker-compose secrets → /run/secrets/ → entrypoint.sh export
```

### 新フロー（3 段）

```
1Password → 1Password Connect → External Secrets Operator → Kubernetes Secret → Pod env/volume
```

### ExternalSecret 定義

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: openclaw-secrets
  namespace: openclaw
spec:
  refreshInterval: 5m
  secretStoreRef:
    name: onepassword
  target:
    name: openclaw-secrets
  data:
    - secretKey: github-token
      remoteRef:
        key: GitHubUsedOpenClawPAT
        property: credential
    - secretKey: xai-api-key
      remoteRef:
        key: xAI-Grok-Twitter
        property: apikey
    - secretKey: gateway-token
      remoteRef:
        key: OpenClaw-Gateway
        property: token
    - secretKey: slack-bot-token
      remoteRef:
        key: SlackBotOpenClaw
        property: token
    - secretKey: telegram-bot-token
      remoteRef:
        key: TelegramBot
        property: token
```

### 初回セットアップ

1. 1Password ウェブ UI から Connect クレデンシャル（`1password-credentials.json`）を生成
2. `task setup` で Kind クラスタ作成 → ESO インストール → 1Password Connect インストール → Connect Token 登録 → ビルド → デプロイ

以降は ESO が 5 分ごとにシークレットを自動同期。

## Gateway Deployment

### セキュリティ

Docker Compose の hardening をそのまま K8s SecurityContext に移行:

| Docker Compose           | Kubernetes                                           |
| ------------------------ | ---------------------------------------------------- |
| `read_only: true`        | `readOnlyRootFilesystem: true`                       |
| `cap_drop: [ALL]`        | `capabilities.drop: [ALL]`                           |
| `no-new-privileges:true` | `allowPrivilegeEscalation: false`                    |
| `user: "1000:1000"`      | `runAsUser: 1000, runAsGroup: 1000`                  |
| `mem_limit: 2g`          | `resources.limits.memory: 2Gi`                       |
| `cpus: 1.0`              | `resources.limits.cpu: "1"`                          |
| `pids_limit: 256`        | _(K8s 未対応、Kind ノードレベルで設定可能)_          |
| `tmpfs: /tmp:size=64m`   | `emptyDir.sizeLimit: 256Mi` （拡大、clone 問題防止） |

### ヘルスチェック

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 41789
  initialDelaySeconds: 60
  periodSeconds: 30
readinessProbe:
  httpGet:
    path: /health
    port: 41789
  initialDelaySeconds: 30
  periodSeconds: 10
```

Docker Compose のヘルスチェックは再起動トリガーにならない。K8s の liveness probe は自動で Pod を再起動するため、auth refresh 失敗のような問題から自動復旧できる。

### 設定注入

openclaw.json を ConfigMap で直接マウント。config 内のシークレット参照（gateway token 等）は init container で `envsubst` して shared volume に書き出す。

### entrypoint.sh の簡素化

**削除（K8s が担当）:**

- シークレット読み取り・export（~35 行）→ K8s Secret env injection
- 設定テンプレートレンダリング（~10 行）→ ConfigMap + init container envsubst
- cron jobs seed ロジック → ConfigMap 直接マウント
- auth profile seeding（~90 行）→ 別途 init container または削除検討

**維持:**

- workspace git clone/pull
- AGENTS.md ポリシー注入
- superpowers clone/wiring
- スキルコピー
- stale skill snapshot 無効化
- ヘルスサマリー出力

**結果:** ~520 行 → ~250 行（半減）

## cognee-skills Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cognee-skills
  namespace: openclaw
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cognee-skills
  template:
    spec:
      containers:
        - name: cognee-skills
          image: local/cognee-skills:dev
          ports:
            - containerPort: 8000
          volumeMounts:
            - name: openclaw-sessions
              mountPath: /openclaw-sessions
          livenessProbe:
            httpGet:
              path: /health
              port: 8000
            periodSeconds: 30
      volumes:
        - name: openclaw-sessions
          persistentVolumeClaim:
            claimName: openclaw-home
```

Gateway config の MCP bridge 接続先: `http://127.0.0.1:8000` → `http://cognee-skills:8000`（同一 namespace 内 Service DNS）

K8s Service DNS により、cognee-skills Pod が ready でない時は明確にエラーになる（現行の無限リトライループが改善）。

## Cron

OpenClaw ビルトインの cron 機能をそのまま使う。jobs.json は ConfigMap で直接マウントする。

理由: OpenClaw の cron はエージェントセッション・メモリと統合されており、K8s CronJob に置き換えると統合が失われる。

ConfigMap の更新は `task deploy`（`kubectl apply -k`）で反映。現行の「Handler が seed 条件をチェックして docker cp」のロジックは完全に不要になる。

## Taskfile

主要タスク:

| タスク                | 内容                                                                   |
| --------------------- | ---------------------------------------------------------------------- |
| `task setup`          | 初回フルセットアップ（クラスタ → ESO → 1Password → ビルド → デプロイ） |
| `task build`          | Docker イメージビルド + Kind ロード                                    |
| `task deploy`         | `kubectl apply -k overlays/local/`                                     |
| `task logs`           | Gateway ログ表示                                                       |
| `task status`         | 全 Pod 状態表示                                                        |
| `task restart`        | Gateway ローリング再起動                                               |
| `task shell`          | Gateway に exec                                                        |
| `task sandbox:ps`     | sandbox コンテナ一覧                                                   |
| `task sandbox:build`  | sandbox イメージビルド                                                 |
| `task cluster:create` | Kind クラスタ作成                                                      |
| `task cluster:delete` | Kind クラスタ削除                                                      |

## dotfiles からの削除対象

移行完了後に dotfiles から削除するファイル:

- `docker/openclaw/` 全体
- `chezmoi/dot_openclaw/` 全体
- `chezmoi/.chezmoidata/openclaw.yaml`
- `scripts/powershell/handlers/Handler.OpenClaw.ps1`
- `scripts/powershell/tests/handlers/Handler.OpenClaw.Tests.ps1`
- `scripts/powershell/handlers/Handler.CogneeSkills.ps1`（OpenClaw 依存）
- `docs/chezmoi/dot_openclaw/` 全体
- `docs/superpowers/specs/` および `plans/` の OpenClaw 関連ドキュメント
- `docs/faq/setup-openclaw.md`
- Taskfile.yml の openclaw/sandbox タスク
- スクリーンショット（`openclaw-*.png`）

## 移行戦略

1. **Phase 1: 新リポ作成・並行運用**
   - `openclaw-k8s` リポジトリを作成
   - Kind + Kustomize 基盤を構築
   - 既存 Docker Compose と並行で動作確認

2. **Phase 2: 機能移行**
   - gateway Deployment + ConfigMap
   - cognee-skills Deployment
   - ExternalSecret によるシークレット管理
   - entrypoint.sh 簡素化
   - Taskfile 整備

3. **Phase 3: dotfiles クリーンアップ**
   - 全 OpenClaw 関連ファイルを dotfiles から削除
   - dotfiles の CLAUDE.md から OpenClaw 参照を削除
   - Handler チェーンから OpenClaw/CogneeSkills を除外

## 制約・前提

- Kind は Windows Docker Desktop 上で動作（WSL2 バックエンド）
- sandbox コンテナは Kind クラスタ外（ホスト Docker）で動作する（現行維持）
- 1Password CLI (`op`) は初回セットアップ時のみ必要（Connect クレデンシャル生成）
- Claude Code/Gemini/Codex の OAuth 認証は Kind extraMount + hostPath volumeMount で対応（現行の bind mount と同等）
