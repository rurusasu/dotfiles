# OpenClaw Kind Migration — Phase 1: リポジトリ作成・Kind 基盤構築

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新リポジトリ `openclaw-k8s` を作成し、Kind クラスタ上で OpenClaw gateway + cognee-skills が起動する状態にする（Docker Compose との並行運用）

**Architecture:** Kind クラスタにKustomize でリソースをデプロイ。シークレットは Phase 1 では手動 Secret で対応し、ESO + 1Password Connect は Phase 2 で導入する。gateway の entrypoint.sh は現行をコピーし、Phase 2 で簡素化する。

**Tech Stack:** Kind, Kustomize, Docker, Taskfile (go-task), kubectl

**Spec:** `docs/superpowers/specs/2026-03-28-openclaw-kind-migration-design.md`

---

### File Structure

```
openclaw-k8s/
├── CLAUDE.md                         # AI エージェント向け開発ルール
├── Taskfile.yml                      # 全操作の統一エントリーポイント
├── kind/
│   └── cluster.yaml                  # Kind クラスタ定義
├── docker/
│   ├── gateway/
│   │   ├── Dockerfile                # dotfiles から移植
│   │   ├── entrypoint.sh            # dotfiles から移植（Phase 1 はそのまま）
│   │   ├── config/
│   │   │   ├── acpx.config.json     # ACPX ランタイム設定
│   │   │   └── gemini.settings.json # Gemini CLI 設定
│   │   ├── hooks/
│   │   │   └── log-skill-execution.js
│   │   └── .dockerignore
│   ├── cognee-skills/
│   │   ├── Dockerfile               # dotfiles から移植
│   │   ├── entrypoint.sh
│   │   └── skills_tools/            # カスタムスキル Python モジュール
│   └── sandbox/
│       └── Dockerfile.custom        # dotfiles から移植
├── base/
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── gateway/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── configmap.yaml           # openclaw.json
│   │   └── pvc.yaml                 # openclaw-home, openclaw-data
│   ├── cognee-skills/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── pvc.yaml                 # cognee-data
│   ├── falkordb/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── pvc.yaml
│   └── cron/
│       └── configmap.yaml           # jobs.json
├── overlays/
│   └── local/
│       ├── kustomization.yaml
│       └── patches/
│           └── gateway-volumes.yaml # Kind 固有 hostPath 設定
└── tests/
    └── smoke-test.sh               # 最小限の起動確認テスト
```

---

### Task 1: リポジトリ初期化

**Files:**

- Create: `openclaw-k8s/CLAUDE.md`
- Create: `openclaw-k8s/.gitignore`

- [ ] **Step 1: GitHub にリポジトリ作成**

```bash
gh repo create rurusasu/openclaw-k8s --private --clone
cd openclaw-k8s
```

- [ ] **Step 2: .gitignore を作成**

```bash
cat > .gitignore << 'EOF'
# Secrets (NEVER commit)
1password-credentials.json
*.secret
.env.local

# Docker
.docker/

# Kind
kubeconfig

# OS
.DS_Store
Thumbs.db

# IDE
.idea/
.vscode/
EOF
```

- [ ] **Step 3: CLAUDE.md を作成**

````bash
cat > CLAUDE.md << 'EOF'
# openclaw-k8s: 開発ルール

## 概要

OpenClaw の Kind (Kubernetes in Docker) デプロイ構成を管理するリポジトリ。

## ディレクトリ構成

- `kind/`: Kind クラスタ定義
- `docker/`: Dockerfile, entrypoint.sh 等のビルド資材
- `base/`: Kustomize ベースマニフェスト
- `overlays/`: 環境固有パッチ
- `tests/`: スモークテスト

## コマンド

```bash
task setup          # 初回フルセットアップ
task build          # イメージビルド + Kind ロード
task deploy         # Kustomize デプロイ
task status         # Pod 状態確認
task logs           # Gateway ログ
task restart        # Gateway 再起動
task cluster:create # Kind クラスタ作成
task cluster:delete # Kind クラスタ削除
````

## ルール

- シークレットを Git にコミットしない
- マニフェスト変更後は `task deploy` で反映
- Docker イメージ変更後は `task build && task deploy` で反映
  EOF

````

- [ ] **Step 4: コミット**

```bash
git add .gitignore CLAUDE.md
git commit -m "init: リポジトリ初期化"
````

---

### Task 2: Kind クラスタ定義

**Files:**

- Create: `openclaw-k8s/kind/cluster.yaml`

- [ ] **Step 1: Kind クラスタ設定を作成**

```bash
mkdir -p kind
cat > kind/cluster.yaml << 'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      # Gateway API → localhost:41789
      - containerPort: 30789
        hostPort: 41789
        protocol: TCP
      # Control UI → localhost:41791
      - containerPort: 30791
        hostPort: 41791
        protocol: TCP
    extraMounts:
      # Docker socket for sandbox container spawning
      - hostPath: /var/run/docker.sock
        containerPath: /var/run/docker.sock
      # Workspace shared between gateway and sandbox
      - hostPath: C:/Users/rurus/openclaw-workspace
        containerPath: /workspace
      # Claude Code OAuth credentials
      - hostPath: C:/Users/rurus/.claude
        containerPath: /host-claude
      # Gemini CLI OAuth credentials
      - hostPath: C:/Users/rurus/.gemini
        containerPath: /host-gemini
      # Codex auth
      - hostPath: C:/Users/rurus/.codex/auth.json
        containerPath: /host-codex-auth.json
      # Claude Code config
      - hostPath: C:/Users/rurus/.claude.json
        containerPath: /host-claude.json
EOF
```

- [ ] **Step 2: クラスタ作成をテスト**

```bash
kind create cluster --name openclaw --config kind/cluster.yaml
```

Expected: `Creating cluster "openclaw" ...` → `Set kubectl context to "kind-openclaw"`

- [ ] **Step 3: クラスタ削除（テストクリーンアップ）**

```bash
kind delete cluster --name openclaw
```

- [ ] **Step 4: コミット**

```bash
git add kind/cluster.yaml
git commit -m "feat: Kind クラスタ定義を追加"
```

---

### Task 3: Taskfile 作成

**Files:**

- Create: `openclaw-k8s/Taskfile.yml`

- [ ] **Step 1: Taskfile を作成**

```bash
cat > Taskfile.yml << 'TASKEOF'
version: "3"

vars:
  CLUSTER_NAME: openclaw
  NAMESPACE: openclaw

tasks:
  # === クラスタ管理 ===
  cluster:create:
    desc: Kind クラスタを作成
    status:
      - kind get clusters 2>/dev/null | grep -q {{.CLUSTER_NAME}}
    cmds:
      - kind create cluster --name {{.CLUSTER_NAME}} --config kind/cluster.yaml
      - kubectl create namespace {{.NAMESPACE}} --dry-run=client -o yaml | kubectl apply -f -

  cluster:delete:
    desc: Kind クラスタを削除
    cmds:
      - kind delete cluster --name {{.CLUSTER_NAME}}

  # === ビルド ===
  build:
    desc: 全イメージをビルドして Kind にロード
    cmds:
      - task: build:gateway
      - task: build:cognee-skills
      - task: build:sandbox

  build:gateway:
    desc: Gateway イメージをビルド
    cmds:
      - docker build -t local/openclaw-gateway:dev docker/gateway/
      - kind load docker-image local/openclaw-gateway:dev --name {{.CLUSTER_NAME}}

  build:cognee-skills:
    desc: cognee-skills イメージをビルド
    cmds:
      - docker build -t local/cognee-skills:dev docker/cognee-skills/
      - kind load docker-image local/cognee-skills:dev --name {{.CLUSTER_NAME}}

  build:sandbox:
    desc: Sandbox イメージをビルド（ホスト Docker 上で直接使用）
    cmds:
      - docker build -t openclaw-sandbox-common:bookworm-slim docker/sandbox/

  # === デプロイ ===
  deploy:
    desc: Kustomize で全リソースをデプロイ
    cmds:
      - kubectl apply -k overlays/local/

  # === 運用 ===
  status:
    desc: 全 Pod の状態を表示
    cmds:
      - kubectl get pods,svc,pvc -n {{.NAMESPACE}} -o wide

  logs:
    desc: Gateway ログを表示
    cmds:
      - kubectl logs -n {{.NAMESPACE}} -l app=openclaw-gateway -f --tail=100

  logs:cognee:
    desc: cognee-skills ログを表示
    cmds:
      - kubectl logs -n {{.NAMESPACE}} -l app=cognee-skills -f --tail=100

  restart:
    desc: Gateway を再起動
    cmds:
      - kubectl rollout restart deployment/openclaw-gateway -n {{.NAMESPACE}}

  shell:
    desc: Gateway に接続
    cmds:
      - kubectl exec -it -n {{.NAMESPACE}} deployment/openclaw-gateway -- sh

  # === sandbox ===
  sandbox:ps:
    desc: sandbox コンテナ一覧
    cmds:
      - docker ps --filter "name=openclaw-sbx" --format "table {{`{{.Names}}`}}\t{{`{{.Status}}`}}\t{{`{{.CreatedAt}}`}}"

  sandbox:gc:
    desc: 終了済み sandbox コンテナを削除
    cmds:
      - docker ps -aq --filter "name=openclaw-sbx" --filter status=exited | xargs -r docker rm

  # === セットアップ ===
  setup:
    desc: 初回フルセットアップ
    cmds:
      - task: cluster:create
      - task: build
      - task: setup:secrets
      - task: deploy
      - echo "Setup complete. Run 'task status' to verify."

  setup:secrets:
    desc: 手動シークレット作成（Phase 1 用、Phase 2 で ESO に置換）
    cmds:
      - |
        echo "Enter GitHub PAT (from 1Password: GitHubUsedOpenClawPAT):"
        read -s GITHUB_TOKEN
        echo "Enter xAI API Key (from 1Password: xAI-Grok-Twitter, or press enter to skip):"
        read -s XAI_API_KEY
        echo "Enter Gateway Token (from 1Password: OpenClaw-Gateway):"
        read -s GATEWAY_TOKEN
        echo "Enter Slack Bot Token (from 1Password: SlackBotOpenClaw):"
        read -s SLACK_BOT_TOKEN
        echo "Enter Telegram Bot Token (from 1Password: TelegramBot):"
        read -s TELEGRAM_BOT_TOKEN
        echo "Enter Gemini API Key (from 1Password, or press enter to skip):"
        read -s GEMINI_API_KEY
        kubectl create secret generic openclaw-secrets -n {{.NAMESPACE}} \
          --from-literal=github-token="$GITHUB_TOKEN" \
          --from-literal=xai-api-key="$XAI_API_KEY" \
          --from-literal=gateway-token="$GATEWAY_TOKEN" \
          --from-literal=slack-bot-token="$SLACK_BOT_TOKEN" \
          --from-literal=telegram-bot-token="$TELEGRAM_BOT_TOKEN" \
          --from-literal=gemini-api-key="$GEMINI_API_KEY" \
          --dry-run=client -o yaml | kubectl apply -f -
        echo "Secrets created/updated in namespace {{.NAMESPACE}}"

  # === テスト ===
  test:smoke:
    desc: スモークテスト実行
    cmds:
      - bash tests/smoke-test.sh
TASKEOF
```

- [ ] **Step 2: task が認識するか確認**

```bash
task --list
```

Expected: 全タスクが一覧表示される

- [ ] **Step 3: コミット**

```bash
git add Taskfile.yml
git commit -m "feat: Taskfile を追加"
```

---

### Task 4: Docker 資材を dotfiles から移植

**Files:**

- Create: `openclaw-k8s/docker/gateway/Dockerfile`
- Create: `openclaw-k8s/docker/gateway/entrypoint.sh`
- Create: `openclaw-k8s/docker/gateway/config/acpx.config.json`
- Create: `openclaw-k8s/docker/gateway/config/gemini.settings.json`
- Create: `openclaw-k8s/docker/gateway/hooks/log-skill-execution.js`
- Create: `openclaw-k8s/docker/gateway/.dockerignore`
- Create: `openclaw-k8s/docker/cognee-skills/Dockerfile`
- Create: `openclaw-k8s/docker/cognee-skills/entrypoint.sh`
- Create: `openclaw-k8s/docker/cognee-skills/skills_tools/` (全ファイル)
- Create: `openclaw-k8s/docker/sandbox/Dockerfile.custom`

- [ ] **Step 1: gateway Docker 資材をコピー**

```bash
mkdir -p docker/gateway/config docker/gateway/hooks
cp /d/ruru/dotfiles/docker/openclaw/Dockerfile docker/gateway/Dockerfile
cp /d/ruru/dotfiles/docker/openclaw/entrypoint.sh docker/gateway/entrypoint.sh
cp /d/ruru/dotfiles/docker/openclaw/config/acpx.config.json docker/gateway/config/
cp /d/ruru/dotfiles/docker/openclaw/config/gemini.settings.json docker/gateway/config/
cp /d/ruru/dotfiles/docker/openclaw/hooks/log-skill-execution.js docker/gateway/hooks/
cp /d/ruru/dotfiles/docker/openclaw/.dockerignore docker/gateway/.dockerignore
```

- [ ] **Step 2: cognee-skills Docker 資材をコピー**

```bash
mkdir -p docker/cognee-skills
cp /d/ruru/dotfiles/docker/cognee-skills/Dockerfile docker/cognee-skills/
cp /d/ruru/dotfiles/docker/cognee-skills/entrypoint.sh docker/cognee-skills/
cp -r /d/ruru/dotfiles/docker/cognee-skills/skills_tools docker/cognee-skills/
```

- [ ] **Step 3: sandbox Dockerfile をコピー**

```bash
mkdir -p docker/sandbox
cp /d/ruru/dotfiles/docker/openclaw/Dockerfile.sandbox-custom docker/sandbox/Dockerfile.custom
```

- [ ] **Step 4: gateway イメージがビルドできるか確認**

```bash
docker build -t local/openclaw-gateway:dev docker/gateway/
```

Expected: ビルド成功

- [ ] **Step 5: cognee-skills イメージがビルドできるか確認**

```bash
docker build -t local/cognee-skills:dev docker/cognee-skills/
```

Expected: ビルド成功

- [ ] **Step 6: コミット**

```bash
git add docker/
git commit -m "feat: Docker 資材を dotfiles から移植"
```

---

### Task 5: Kustomize ベースマニフェスト — namespace, PVC

**Files:**

- Create: `openclaw-k8s/base/namespace.yaml`
- Create: `openclaw-k8s/base/gateway/pvc.yaml`
- Create: `openclaw-k8s/base/cognee-skills/pvc.yaml`
- Create: `openclaw-k8s/base/falkordb/pvc.yaml`

- [ ] **Step 1: namespace を作成**

```bash
mkdir -p base
cat > base/namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: openclaw
EOF
```

- [ ] **Step 2: gateway PVC を作成**

```bash
mkdir -p base/gateway
cat > base/gateway/pvc.yaml << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: openclaw-home
  namespace: openclaw
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 5Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: openclaw-data
  namespace: openclaw
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 10Gi
EOF
```

- [ ] **Step 3: cognee-skills PVC を作成**

```bash
mkdir -p base/cognee-skills
cat > base/cognee-skills/pvc.yaml << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: cognee-data
  namespace: openclaw
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 5Gi
EOF
```

- [ ] **Step 4: FalkorDB PVC を作成**

```bash
mkdir -p base/falkordb
cat > base/falkordb/pvc.yaml << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: falkordb-data
  namespace: openclaw
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 2Gi
EOF
```

- [ ] **Step 5: コミット**

```bash
git add base/
git commit -m "feat: namespace と PVC マニフェストを追加"
```

---

### Task 6: FalkorDB Deployment + Service

**Files:**

- Create: `openclaw-k8s/base/falkordb/deployment.yaml`
- Create: `openclaw-k8s/base/falkordb/service.yaml`

- [ ] **Step 1: FalkorDB Deployment を作成**

```bash
cat > base/falkordb/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: falkordb
  namespace: openclaw
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: falkordb
  template:
    metadata:
      labels:
        app: falkordb
    spec:
      containers:
        - name: falkordb
          image: falkordb/falkordb:v4.4.1
          ports:
            - containerPort: 6379
          volumeMounts:
            - name: falkordb-data
              mountPath: /data
          readinessProbe:
            exec:
              command: ["redis-cli", "ping"]
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            exec:
              command: ["redis-cli", "ping"]
            initialDelaySeconds: 15
            periodSeconds: 30
          resources:
            limits:
              memory: 1Gi
              cpu: "0.5"
      volumes:
        - name: falkordb-data
          persistentVolumeClaim:
            claimName: falkordb-data
EOF
```

- [ ] **Step 2: FalkorDB Service を作成**

```bash
cat > base/falkordb/service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: falkordb
  namespace: openclaw
spec:
  selector:
    app: falkordb
  ports:
    - port: 6379
      targetPort: 6379
EOF
```

- [ ] **Step 3: コミット**

```bash
git add base/falkordb/
git commit -m "feat: FalkorDB Deployment + Service を追加"
```

---

### Task 7: cognee-skills Deployment + Service

**Files:**

- Create: `openclaw-k8s/base/cognee-skills/deployment.yaml`
- Create: `openclaw-k8s/base/cognee-skills/service.yaml`

- [ ] **Step 1: cognee-skills Deployment を作成**

```bash
cat > base/cognee-skills/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cognee-skills
  namespace: openclaw
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: cognee-skills
  template:
    metadata:
      labels:
        app: cognee-skills
    spec:
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
      containers:
        - name: cognee-skills
          image: local/cognee-skills:dev
          imagePullPolicy: Never
          ports:
            - containerPort: 8000
          env:
            - name: TRANSPORT_MODE
              value: http
            - name: LLM_PROVIDER
              value: gemini
            - name: EMBEDDING_PROVIDER
              value: gemini
            - name: EMBEDDING_MODEL
              value: gemini-embedding-2-preview
            - name: GRAPH_DATABASE_PROVIDER
              value: falkordb
            - name: GRAPH_DATABASE_URL
              value: "bolt://falkordb:6379"
            - name: VECTOR_DB_PROVIDER
              value: lancedb
            - name: SKILL_HEALTH_WINDOW
              value: "20"
            - name: SKILL_HEALTH_THRESHOLD
              value: "0.7"
            - name: SKILL_CORRECTION_PENALTY
              value: "0.05"
            - name: LLM_API_KEY
              valueFrom:
                secretKeyRef:
                  name: openclaw-secrets
                  key: gemini-api-key
                  optional: true
            - name: EMBEDDING_API_KEY
              valueFrom:
                secretKeyRef:
                  name: openclaw-secrets
                  key: gemini-api-key
                  optional: true
          volumeMounts:
            - name: openclaw-home
              mountPath: /openclaw-sessions
              subPath: agents
              readOnly: true
            - name: cognee-data
              mountPath: /app/data
          readinessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 10
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 30
            periodSeconds: 30
          resources:
            limits:
              memory: 1Gi
              cpu: "0.5"
      volumes:
        - name: openclaw-home
          persistentVolumeClaim:
            claimName: openclaw-home
        - name: cognee-data
          persistentVolumeClaim:
            claimName: cognee-data
EOF
```

- [ ] **Step 2: cognee-skills Service を作成**

```bash
cat > base/cognee-skills/service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: cognee-skills
  namespace: openclaw
spec:
  selector:
    app: cognee-skills
  ports:
    - port: 8000
      targetPort: 8000
EOF
```

- [ ] **Step 3: コミット**

```bash
git add base/cognee-skills/deployment.yaml base/cognee-skills/service.yaml
git commit -m "feat: cognee-skills Deployment + Service を追加"
```

---

### Task 8: Gateway ConfigMap + Cron ConfigMap

**Files:**

- Create: `openclaw-k8s/base/gateway/configmap.yaml`
- Create: `openclaw-k8s/base/cron/configmap.yaml`

- [ ] **Step 1: Gateway ConfigMap を作成**

dotfiles の `chezmoi/dot_openclaw/openclaw.docker.json.tmpl` からレンダリング済み JSON を取得し、以下を変更:

- MCP bridge URL: `http://127.0.0.1:8000` → `http://cognee-skills:8000`
- シークレットプレースホルダ: `@@GITHUB_TOKEN@@` → `${GITHUB_TOKEN}` (envsubst 用)
- `@@GATEWAY_TOKEN@@` → `${GATEWAY_TOKEN}`
- `@@SLACK_BOT_TOKEN@@` → `${SLACK_BOT_TOKEN}`
- `@@TELEGRAM_BOT_TOKEN@@` → `${TELEGRAM_BOT_TOKEN}`

```bash
cat > base/gateway/configmap.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: openclaw-config
  namespace: openclaw
data:
  openclaw.json.tmpl: |
    <レンダリング済み openclaw.json の内容をここに貼り付け>
    <シークレット値は ${ENV_VAR} 形式のプレースホルダ>
EOF
```

Note: 実際の JSON 内容は dotfiles の現行設定ファイルからコピーする。chezmoi テンプレートではなく、レンダリング済み JSON を使用。

- [ ] **Step 2: Cron ConfigMap を作成**

dotfiles の `chezmoi/dot_openclaw/cron/jobs.seed.json.tmpl` からレンダリング済み JSON を取得。

```bash
mkdir -p base/cron
cat > base/cron/configmap.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: openclaw-cron
  namespace: openclaw
data:
  jobs.json: |
    <レンダリング済み jobs.json の内容をここに貼り付け>
EOF
```

Note: Telegram user ID 等はレンダリング済みの値をそのまま使用。

- [ ] **Step 3: コミット**

```bash
git add base/gateway/configmap.yaml base/cron/configmap.yaml
git commit -m "feat: Gateway 設定と Cron ジョブの ConfigMap を追加"
```

---

### Task 9: Gateway Deployment + Service

**Files:**

- Create: `openclaw-k8s/base/gateway/deployment.yaml`
- Create: `openclaw-k8s/base/gateway/service.yaml`

- [ ] **Step 1: Gateway Deployment を作成**

```bash
cat > base/gateway/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: openclaw-gateway
  namespace: openclaw
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: openclaw-gateway
  template:
    metadata:
      labels:
        app: openclaw-gateway
    spec:
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
      initContainers:
        # envsubst でシークレットを config に注入
        - name: config-renderer
          image: busybox:1.37
          command: ["sh", "-c"]
          args:
            - |
              # busybox の envsubst は無いので sed で代替
              cp /config-tmpl/openclaw.json.tmpl /config-out/openclaw.json
              sed -i "s|\${GITHUB_TOKEN}|$GITHUB_TOKEN|g" /config-out/openclaw.json
              sed -i "s|\${GATEWAY_TOKEN}|$GATEWAY_TOKEN|g" /config-out/openclaw.json
              sed -i "s|\${SLACK_BOT_TOKEN}|$SLACK_BOT_TOKEN|g" /config-out/openclaw.json
              sed -i "s|\${TELEGRAM_BOT_TOKEN}|$TELEGRAM_BOT_TOKEN|g" /config-out/openclaw.json
          env:
            - name: GITHUB_TOKEN
              valueFrom:
                secretKeyRef:
                  name: openclaw-secrets
                  key: github-token
            - name: GATEWAY_TOKEN
              valueFrom:
                secretKeyRef:
                  name: openclaw-secrets
                  key: gateway-token
            - name: SLACK_BOT_TOKEN
              valueFrom:
                secretKeyRef:
                  name: openclaw-secrets
                  key: slack-bot-token
            - name: TELEGRAM_BOT_TOKEN
              valueFrom:
                secretKeyRef:
                  name: openclaw-secrets
                  key: telegram-bot-token
          volumeMounts:
            - name: config-tmpl
              mountPath: /config-tmpl
            - name: config-rendered
              mountPath: /config-out
      containers:
        - name: gateway
          image: local/openclaw-gateway:dev
          imagePullPolicy: Never
          ports:
            - containerPort: 41789
              name: api
            - containerPort: 41791
              name: control-ui
          env:
            - name: GITHUB_TOKEN
              valueFrom:
                secretKeyRef:
                  name: openclaw-secrets
                  key: github-token
            - name: GH_TOKEN
              valueFrom:
                secretKeyRef:
                  name: openclaw-secrets
                  key: github-token
            - name: XAI_API_KEY
              valueFrom:
                secretKeyRef:
                  name: openclaw-secrets
                  key: xai-api-key
                  optional: true
            - name: TZ
              value: Asia/Tokyo
            - name: HOME
              value: /home/app
            - name: GIT_ASKPASS
              value: /usr/local/bin/git-credential-askpass.sh
            - name: NODE_OPTIONS
              value: --max-old-space-size=1536
            - name: OPENCLAW_SANDBOX
              value: "1"
            - name: OPENCLAW_LOG_LEVEL
              value: trace
            - name: OPENCLAW_WORKSPACE_POSIX
              value: /workspace
          volumeMounts:
            - name: openclaw-home
              mountPath: /home/app/.openclaw
            - name: openclaw-data
              mountPath: /app/data
            - name: workspace
              mountPath: /workspace
            - name: docker-sock
              mountPath: /var/run/docker.sock
            - name: config-rendered
              mountPath: /home/app/.openclaw/openclaw.json
              subPath: openclaw.json
              readOnly: true
            - name: cron-config
              mountPath: /home/app/.openclaw/cron/jobs.json
              subPath: jobs.json
            - name: claude-credentials
              mountPath: /home/app/.claude
            - name: claude-config
              mountPath: /home/app/.claude.json
              subPath: .claude.json
              readOnly: true
            - name: tmp
              mountPath: /tmp
          resources:
            limits:
              memory: 2Gi
              cpu: "1"
          securityContext:
            readOnlyRootFilesystem: true
            allowPrivilegeEscalation: false
            capabilities:
              drop: [ALL]
          livenessProbe:
            httpGet:
              path: /health
              port: 41789
            initialDelaySeconds: 60
            periodSeconds: 30
            failureThreshold: 5
          readinessProbe:
            httpGet:
              path: /health
              port: 41789
            initialDelaySeconds: 30
            periodSeconds: 10
      volumes:
        - name: openclaw-home
          persistentVolumeClaim:
            claimName: openclaw-home
        - name: openclaw-data
          persistentVolumeClaim:
            claimName: openclaw-data
        - name: workspace
          hostPath:
            path: /workspace
        - name: docker-sock
          hostPath:
            path: /var/run/docker.sock
        - name: config-tmpl
          configMap:
            name: openclaw-config
        - name: config-rendered
          emptyDir: {}
        - name: cron-config
          configMap:
            name: openclaw-cron
        - name: claude-credentials
          hostPath:
            path: /host-claude
        - name: claude-config
          hostPath:
            path: /host-claude.json
        - name: tmp
          emptyDir:
            sizeLimit: 256Mi
EOF
```

- [ ] **Step 2: Gateway Service を作成**

```bash
cat > base/gateway/service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: openclaw-gateway
  namespace: openclaw
spec:
  type: NodePort
  selector:
    app: openclaw-gateway
  ports:
    - name: api
      port: 41789
      targetPort: 41789
      nodePort: 30789
    - name: control-ui
      port: 41791
      targetPort: 41791
      nodePort: 30791
EOF
```

- [ ] **Step 3: コミット**

```bash
git add base/gateway/deployment.yaml base/gateway/service.yaml
git commit -m "feat: Gateway Deployment + Service を追加"
```

---

### Task 10: Kustomize 構成

**Files:**

- Create: `openclaw-k8s/base/kustomization.yaml`
- Create: `openclaw-k8s/overlays/local/kustomization.yaml`

- [ ] **Step 1: base kustomization を作成**

```bash
cat > base/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - gateway/pvc.yaml
  - gateway/configmap.yaml
  - gateway/deployment.yaml
  - gateway/service.yaml
  - cognee-skills/pvc.yaml
  - cognee-skills/deployment.yaml
  - cognee-skills/service.yaml
  - falkordb/pvc.yaml
  - falkordb/deployment.yaml
  - falkordb/service.yaml
  - cron/configmap.yaml
EOF
```

- [ ] **Step 2: local overlay を作成**

```bash
mkdir -p overlays/local
cat > overlays/local/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base
EOF
```

- [ ] **Step 3: Kustomize ビルドを検証**

```bash
kubectl kustomize overlays/local/ > /dev/null
```

Expected: エラーなし

- [ ] **Step 4: コミット**

```bash
git add base/kustomization.yaml overlays/
git commit -m "feat: Kustomize base + local overlay を追加"
```

---

### Task 11: スモークテスト

**Files:**

- Create: `openclaw-k8s/tests/smoke-test.sh`

- [ ] **Step 1: スモークテストを作成**

```bash
mkdir -p tests
cat > tests/smoke-test.sh << 'TESTEOF'
#!/bin/bash
set -euo pipefail

NAMESPACE="openclaw"
TIMEOUT=120

echo "=== OpenClaw Kind Smoke Test ==="

# 1. クラスタが存在するか
echo -n "[1/5] Kind cluster exists... "
if kind get clusters 2>/dev/null | grep -q openclaw; then
  echo "OK"
else
  echo "FAIL: cluster 'openclaw' not found"
  exit 1
fi

# 2. namespace が存在するか
echo -n "[2/5] Namespace exists... "
if kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
  echo "OK"
else
  echo "FAIL: namespace '$NAMESPACE' not found"
  exit 1
fi

# 3. Pod が Running になるまで待機
echo -n "[3/5] Waiting for pods to be ready (max ${TIMEOUT}s)... "
if kubectl wait --for=condition=ready pod -l app=openclaw-gateway -n "$NAMESPACE" --timeout="${TIMEOUT}s" 2>/dev/null; then
  echo "OK"
else
  echo "FAIL: gateway pod not ready"
  kubectl get pods -n "$NAMESPACE"
  exit 1
fi

# 4. Gateway health check
echo -n "[4/5] Gateway health check... "
HEALTH=$(kubectl exec -n "$NAMESPACE" deployment/openclaw-gateway -- curl -sf --max-time 5 http://localhost:41789/health 2>/dev/null || true)
if [ -n "$HEALTH" ]; then
  echo "OK"
else
  echo "FAIL: /health did not respond"
  exit 1
fi

# 5. cognee-skills が起動しているか（optional、起動が遅い場合はスキップ）
echo -n "[5/5] cognee-skills pod status... "
CS_STATUS=$(kubectl get pod -l app=cognee-skills -n "$NAMESPACE" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
if [ "$CS_STATUS" = "Running" ]; then
  echo "OK (Running)"
elif [ "$CS_STATUS" = "Pending" ]; then
  echo "WARN (still Pending, may need more time)"
else
  echo "INFO ($CS_STATUS)"
fi

echo ""
echo "=== Smoke test passed ==="
TESTEOF
chmod +x tests/smoke-test.sh
```

- [ ] **Step 2: コミット**

```bash
git add tests/
git commit -m "feat: スモークテストを追加"
```

---

### Task 12: フルセットアップ実行・動作確認

- [ ] **Step 1: 既存 Docker Compose の OpenClaw を停止**

```bash
docker compose -f /d/ruru/dotfiles/docker/openclaw/docker-compose.yml down
```

- [ ] **Step 2: Kind クラスタ作成 + シークレット登録 + ビルド + デプロイ**

```bash
cd openclaw-k8s
task setup
```

`task setup:secrets` で対話的にシークレットを入力する。

- [ ] **Step 3: Pod の状態を確認**

```bash
task status
```

Expected: openclaw-gateway, cognee-skills, falkordb の 3 Pod が Running

- [ ] **Step 4: スモークテスト実行**

```bash
task test:smoke
```

Expected: 全チェック PASS

- [ ] **Step 5: Gateway ログで正常起動を確認**

```bash
task logs
```

Expected: `[entrypoint]` ログが出力され、`[slack] socket mode connected` が表示される

- [ ] **Step 6: localhost:41789/health にアクセス確認**

```bash
curl -sf http://localhost:41789/health
```

Expected: HTTP 200

- [ ] **Step 7: 問題なければコミット（設定調整があった場合）**

```bash
git add -A
git commit -m "fix: セットアップ時の調整"
```

---

### Task 13: 最終コミット + push

- [ ] **Step 1: 全変更が入っているか確認**

```bash
git log --oneline
git status
```

- [ ] **Step 2: push**

```bash
git push -u origin main
```

Expected: GitHub に push 成功

---

## Phase 1 完了条件

- [ ] `openclaw-k8s` リポジトリが GitHub に存在する
- [ ] `task setup` で Kind クラスタ + 全コンポーネントが起動する
- [ ] Gateway の `/health` が 200 を返す
- [ ] Slack socket mode が接続される
- [ ] `task test:smoke` が PASS する
- [ ] sandbox コンテナが正常に生成される（Slack からメッセージ送信で確認）

## 次のフェーズ

- **Phase 2:** ESO + 1Password Connect 導入、entrypoint.sh 簡素化、dotfiles クリーンアップ
- **Phase 3:** dotfiles からの完全削除、ドキュメント整備
