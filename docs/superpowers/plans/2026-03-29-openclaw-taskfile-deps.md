# Taskfile 依存ツール自動管理 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Taskfile タスクの依存ツール (kind, helm, kubectl, jq, docker) を OS 検出して自動インストールする仕組みを構築する。

**Architecture:** `tasks/deps/detect-os.sh` が OS を判定 (darwin/nixos/wsl2/linux/windows)、`tasks/deps/install-tool.sh` が OS に応じたパッケージマネージャでツールをインストール。`tasks/deps/deps.yml` が Taskfile タスクとしてラップし、各タスクファイルが `deps:` で依存宣言する。

**Tech Stack:** Taskfile (go-task), Bash, winget/brew/apt/nix/curl

**Working directory:** `D:\ruru\openclaw-k8s`

---

## File Structure

| Action | File                           | Responsibility                                   |
| ------ | ------------------------------ | ------------------------------------------------ |
| Create | `tasks/deps/detect-os.sh`      | OS 検出 → stdout に識別子出力                    |
| Create | `tasks/deps/install-tool.sh`   | ツール名 + OS → インストール実行                 |
| Create | `tasks/deps/deps.yml`          | Taskfile タスク定義 (deps:kind, deps:helm, etc.) |
| Create | `tasks/deps/test-detect-os.sh` | detect-os.sh のテスト                            |
| Create | `tasks/deps/test-install.sh`   | install-tool.sh の dry-run テスト                |
| Modify | `Taskfile.yml`                 | includes に deps 追加                            |
| Modify | `tasks/cluster.yml`            | deps: [deps:kind, deps:kubectl] 追加             |
| Modify | `tasks/build.yml`              | deps: [deps:docker] 追加                         |
| Modify | `tasks/deploy.yml`             | deps: [deps:kubectl] 追加                        |
| Modify | `tasks/ops.yml`                | deps: [deps:kubectl] 追加                        |
| Modify | `tasks/sandbox.yml`            | deps: [deps:docker] 追加                         |
| Modify | `tasks/secrets.yml`            | deps 追加 (helm, kubectl, jq)                    |
| Modify | `tasks/test.yml`               | deps:test タスク追加                             |

---

### Task 1: detect-os.sh の作成とテスト

**Files:**

- Create: `tasks/deps/detect-os.sh`
- Create: `tasks/deps/test-detect-os.sh`

- [ ] **Step 1: Write test-detect-os.sh**

```bash
#!/bin/bash
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DETECT="$SCRIPT_DIR/detect-os.sh"

passed=0
failed=0
total=0

assert() {
  local desc="$1"
  total=$((total + 1))
  if eval "$2"; then
    passed=$((passed + 1))
    printf "  PASS: %s\n" "$desc"
  else
    failed=$((failed + 1))
    printf "  FAIL: %s\n" "$desc" >&2
  fi
}

printf "\n=== detect-os.sh ===\n"

# Test: script exists and is executable
assert "detect-os.sh exists" '[ -f "$DETECT" ]'

# Test: exits with 0
result=$("$DETECT" 2>/dev/null) || true
exit_code=0
"$DETECT" >/dev/null 2>&1 || exit_code=$?
assert "exits with code 0" '[ "$exit_code" -eq 0 ]'

# Test: output is non-empty
assert "output is non-empty" '[ -n "$result" ]'

# Test: output is single line
line_count=$(echo "$result" | wc -l | tr -d ' ')
assert "output is single line ($line_count)" '[ "$line_count" -eq 1 ]'

# Test: output is one of the allowed values
case "$result" in
  darwin|nixos|wsl2|linux|windows)
    assert "output is valid OS identifier ($result)" 'true'
    ;;
  *)
    assert "output is valid OS identifier (got: $result)" 'false'
    ;;
esac

# Test: no trailing whitespace or newline in output
trimmed=$(printf "%s" "$result")
assert "no trailing whitespace" '[ "$result" = "$trimmed" ]'

printf "\n=======================================\n"
printf "  Results: %d passed, %d failed / %d total\n" "$passed" "$failed" "$total"
printf "=======================================\n"

[ "$failed" -eq 0 ] || exit 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /d/ruru/openclaw-k8s && bash tasks/deps/test-detect-os.sh`

Expected: FAIL — `detect-os.sh` does not exist yet.

- [ ] **Step 3: Write detect-os.sh**

```bash
#!/bin/bash
set -eu

# Detect OS and print identifier to stdout.
# Output: darwin / nixos / wsl2 / linux / windows
# Exit 1 if unknown.

uname_s="$(uname -s 2>/dev/null || echo unknown)"

case "$uname_s" in
  Darwin)
    echo "darwin"
    ;;
  Linux)
    # NixOS check (before WSL2 — NixOS can run in WSL2 too)
    if [ -f /etc/os-release ] && grep -qi '^ID=nixos' /etc/os-release 2>/dev/null; then
      echo "nixos"
    elif [ -f /proc/version ] && grep -qi 'microsoft\|WSL' /proc/version 2>/dev/null; then
      echo "wsl2"
    else
      echo "linux"
    fi
    ;;
  MINGW*|MSYS*|CYGWIN*)
    echo "windows"
    ;;
  *)
    if [ -n "${MSYSTEM:-}" ]; then
      echo "windows"
    else
      echo "[FATAL] Unknown OS: $uname_s" >&2
      exit 1
    fi
    ;;
esac
```

- [ ] **Step 4: Make executable and run test**

Run: `chmod +x tasks/deps/detect-os.sh && bash tasks/deps/test-detect-os.sh`

Expected: All tests PASS. Output shows `windows` (current environment is MINGW64).

- [ ] **Step 5: Commit**

```bash
git add tasks/deps/detect-os.sh tasks/deps/test-detect-os.sh
git commit -m "feat: add OS detection script with tests"
```

---

### Task 2: install-tool.sh の作成とテスト

**Files:**

- Create: `tasks/deps/install-tool.sh`
- Create: `tasks/deps/test-install.sh`

- [ ] **Step 1: Write test-install.sh**

```bash
#!/bin/bash
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL="$SCRIPT_DIR/install-tool.sh"

passed=0
failed=0
total=0

assert() {
  local desc="$1"
  total=$((total + 1))
  if eval "$2"; then
    passed=$((passed + 1))
    printf "  PASS: %s\n" "$desc"
  else
    failed=$((failed + 1))
    printf "  FAIL: %s\n" "$desc" >&2
  fi
}

printf "\n=== install-tool.sh ===\n"

# Test: script exists
assert "install-tool.sh exists" '[ -f "$INSTALL" ]'

# Test: --dry-run for each tool produces output
for tool in kind helm kubectl jq docker; do
  output=$("$INSTALL" "$tool" --dry-run 2>&1) || true
  assert "--dry-run $tool produces output" '[ -n "$output" ]'
done

# Test: --dry-run does NOT actually install (check by verifying "DRY RUN" in output)
for tool in kind helm kubectl jq; do
  output=$("$INSTALL" "$tool" --dry-run 2>&1) || true
  assert "--dry-run $tool contains DRY RUN marker" 'echo "$output" | grep -qi "dry.run\|would run\|DRY RUN"'
done

# Test: docker shows install instructions (not auto-install)
docker_output=$("$INSTALL" docker --dry-run 2>&1) || true
assert "docker shows manual install message" 'echo "$docker_output" | grep -qi "manual\|install.*docker\|docker desktop"'

# Test: unknown tool exits with error
if "$INSTALL" nonexistent --dry-run >/dev/null 2>&1; then
  assert "unknown tool exits with error" 'false'
else
  assert "unknown tool exits with error" 'true'
fi

# Test: output contains OS-appropriate package manager
current_os=$("$SCRIPT_DIR/detect-os.sh")
case "$current_os" in
  windows)
    output=$("$INSTALL" kind --dry-run 2>&1) || true
    assert "windows: uses winget" 'echo "$output" | grep -qi "winget"'
    ;;
  darwin)
    output=$("$INSTALL" kind --dry-run 2>&1) || true
    assert "darwin: uses brew" 'echo "$output" | grep -qi "brew"'
    ;;
  nixos)
    output=$("$INSTALL" kind --dry-run 2>&1) || true
    assert "nixos: uses nix" 'echo "$output" | grep -qi "nix"'
    ;;
  wsl2|linux)
    output=$("$INSTALL" kind --dry-run 2>&1) || true
    assert "$current_os: uses curl or apt" 'echo "$output" | grep -qiE "curl|apt"'
    ;;
esac

printf "\n=======================================\n"
printf "  Results: %d passed, %d failed / %d total\n" "$passed" "$failed" "$total"
printf "=======================================\n"

[ "$failed" -eq 0 ] || exit 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tasks/deps/test-install.sh`

Expected: FAIL — `install-tool.sh` does not exist yet.

- [ ] **Step 3: Write install-tool.sh**

```bash
#!/bin/bash
set -eu

# Install a tool using the appropriate package manager for the current OS.
# Usage: install-tool.sh <tool-name> [--dry-run]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOL="${1:-}"
DRY_RUN=false
if [ "${2:-}" = "--dry-run" ]; then
  DRY_RUN=true
fi

if [ -z "$TOOL" ]; then
  echo "[FATAL] Usage: install-tool.sh <tool-name> [--dry-run]" >&2
  exit 1
fi

OS="$("$SCRIPT_DIR/detect-os.sh")"

run_cmd() {
  if $DRY_RUN; then
    echo "[DRY RUN] Would run: $*"
  else
    echo "[install] Running: $*"
    eval "$@"
  fi
}

install_kind() {
  case "$OS" in
    windows) run_cmd "winget install --id Kubernetes.kind -e --accept-source-agreements --accept-package-agreements" ;;
    wsl2|linux) run_cmd "curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64 && chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind" ;;
    nixos) run_cmd "nix profile install nixpkgs#kind" ;;
    darwin) run_cmd "brew install kind" ;;
  esac
}

install_helm() {
  case "$OS" in
    windows) run_cmd "winget install --id Helm.Helm -e --accept-source-agreements --accept-package-agreements" ;;
    wsl2|linux) run_cmd 'curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash' ;;
    nixos) run_cmd "nix profile install nixpkgs#kubernetes-helm" ;;
    darwin) run_cmd "brew install helm" ;;
  esac
}

install_kubectl() {
  case "$OS" in
    windows) run_cmd "winget install --id Kubernetes.kubectl -e --accept-source-agreements --accept-package-agreements" ;;
    wsl2|linux) run_cmd 'curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && chmod +x kubectl && sudo mv kubectl /usr/local/bin/kubectl' ;;
    nixos) run_cmd "nix profile install nixpkgs#kubectl" ;;
    darwin) run_cmd "brew install kubectl" ;;
  esac
}

install_jq() {
  case "$OS" in
    windows) run_cmd "winget install --id jqlang.jq -e --accept-source-agreements --accept-package-agreements" ;;
    wsl2|linux) run_cmd "sudo apt-get update -qq && sudo apt-get install -y jq" ;;
    nixos) run_cmd "nix profile install nixpkgs#jq" ;;
    darwin) run_cmd "brew install jq" ;;
  esac
}

install_docker() {
  echo ""
  echo "========================================="
  echo "  Docker requires manual installation"
  echo "========================================="
  case "$OS" in
    windows) echo "  Install Docker Desktop for Windows:" ; echo "  https://docs.docker.com/desktop/setup/install/windows-install/" ;;
    wsl2)    echo "  Install Docker Desktop for Windows (WSL2 backend):" ; echo "  https://docs.docker.com/desktop/setup/install/windows-install/" ;;
    linux)   echo "  Install Docker Engine:" ; echo "  https://docs.docker.com/engine/install/" ;;
    nixos)   echo "  Add to NixOS configuration:" ; echo "  virtualisation.docker.enable = true;" ;;
    darwin)  echo "  Install Docker Desktop for Mac:" ; echo "  https://docs.docker.com/desktop/setup/install/mac-install/" ;;
  esac
  echo "========================================="
  if ! $DRY_RUN; then
    exit 1
  fi
}

case "$TOOL" in
  kind)    install_kind ;;
  helm)    install_helm ;;
  kubectl) install_kubectl ;;
  jq)      install_jq ;;
  docker)  install_docker ;;
  *)
    echo "[FATAL] Unknown tool: $TOOL" >&2
    echo "  Supported: kind, helm, kubectl, jq, docker" >&2
    exit 1
    ;;
esac

# Post-install verification (skip for dry-run and docker)
if ! $DRY_RUN && [ "$TOOL" != "docker" ]; then
  if command -v "$TOOL" >/dev/null 2>&1; then
    echo "[install] $TOOL installed successfully: $(command -v "$TOOL")"
  else
    echo "[WARN] $TOOL was installed but not found in PATH." >&2
    echo "  You may need to restart your shell or add it to PATH." >&2
    exit 1
  fi
fi
```

- [ ] **Step 4: Make executable and run test**

Run: `chmod +x tasks/deps/install-tool.sh && bash tasks/deps/test-install.sh`

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add tasks/deps/install-tool.sh tasks/deps/test-install.sh
git commit -m "feat: add cross-platform tool installer with tests"
```

---

### Task 3: deps.yml の作成

**Files:**

- Create: `tasks/deps/deps.yml`
- Modify: `Taskfile.yml`

- [ ] **Step 1: Write deps.yml**

```yaml
version: "3"

tasks:
  kind:
    desc: kind をインストール (未検出時のみ)
    status:
      - command -v kind
    cmds:
      - bash tasks/deps/install-tool.sh kind

  helm:
    desc: helm をインストール (未検出時のみ)
    status:
      - command -v helm
    cmds:
      - bash tasks/deps/install-tool.sh helm

  kubectl:
    desc: kubectl をインストール (未検出時のみ)
    status:
      - command -v kubectl
    cmds:
      - bash tasks/deps/install-tool.sh kubectl

  jq:
    desc: jq をインストール (未検出時のみ)
    status:
      - command -v jq
    cmds:
      - bash tasks/deps/install-tool.sh jq

  docker:
    desc: docker の存在確認 (未検出時はインストール手順を表示)
    status:
      - command -v docker
    cmds:
      - bash tasks/deps/install-tool.sh docker

  all:
    desc: 全依存ツールをインストール
    deps: [kind, helm, kubectl, jq, docker]

  test:
    desc: deps テストを実行
    cmds:
      - bash tasks/deps/test-detect-os.sh
      - bash tasks/deps/test-install.sh
```

- [ ] **Step 2: Add deps include to Taskfile.yml**

In `Taskfile.yml`, add `deps` as the first include:

```yaml
includes:
  deps:
    taskfile: tasks/deps/deps.yml
  cluster:
    taskfile: tasks/cluster.yml
    ...
```

- [ ] **Step 3: Verify task list**

Run: `task --list`

Expected: `deps:kind`, `deps:helm`, `deps:kubectl`, `deps:jq`, `deps:docker`, `deps:all`, `deps:test` visible in the list.

- [ ] **Step 4: Test a deps task**

Run: `task deps:kubectl`

Expected: `Task is up to date` (kubectl is already installed) or installs it.

- [ ] **Step 5: Commit**

```bash
git add tasks/deps/deps.yml Taskfile.yml
git commit -m "feat: add deps.yml Taskfile integration"
```

---

### Task 4: 既存タスクに deps 依存を追加

**Files:**

- Modify: `tasks/cluster.yml`
- Modify: `tasks/build.yml`
- Modify: `tasks/deploy.yml`
- Modify: `tasks/ops.yml`
- Modify: `tasks/sandbox.yml`
- Modify: `tasks/secrets.yml`

- [ ] **Step 1: Update cluster.yml**

```yaml
version: "3"

tasks:
  create:
    desc: Kind クラスタを作成
    deps: [deps:kind, deps:kubectl]
    status:
      - kind get clusters 2>/dev/null | grep -q "^{{.CLUSTER_NAME}}$"
    cmds:
      - kind create cluster --name {{.CLUSTER_NAME}} --config kind/cluster.yaml
      - kubectl create namespace {{.NAMESPACE}} --dry-run=client -o yaml | kubectl apply -f -

  delete:
    desc: Kind クラスタを削除
    deps: [deps:kind]
    cmds:
      - kind delete cluster --name {{.CLUSTER_NAME}}
```

- [ ] **Step 2: Update build.yml**

```yaml
version: "3"

tasks:
  all:
    desc: 全イメージをビルド + Kind ロード
    deps:
      - gateway
      - cognee-skills
      - sandbox

  gateway:
    desc: Gateway イメージをビルドして Kind にロード
    deps: [deps:docker]
    cmds:
      - docker build -t local/openclaw-gateway:dev docker/gateway/
      - kind load docker-image local/openclaw-gateway:dev --name {{.CLUSTER_NAME}}

  cognee-skills:
    desc: Cognee Skills イメージをビルドして Kind にロード
    deps: [deps:docker]
    cmds:
      - docker build -t local/cognee-skills:dev docker/cognee-skills/
      - kind load docker-image local/cognee-skills:dev --name {{.CLUSTER_NAME}}

  sandbox:
    desc: Sandbox イメージをホスト Docker 上でビルド
    deps: [deps:docker]
    cmds:
      - docker build -t local/openclaw-sandbox:dev docker/sandbox/
```

- [ ] **Step 3: Update deploy.yml**

```yaml
version: "3"

tasks:
  apply:
    desc: Kustomize でデプロイ
    deps: [deps:kubectl]
    cmds:
      - kubectl apply -k overlays/local/
```

- [ ] **Step 4: Update ops.yml**

Add `deps: [deps:kubectl]` to every task:

```yaml
version: "3"

tasks:
  status:
    desc: Pod 状態確認
    deps: [deps:kubectl]
    cmds:
      - kubectl get pods -n {{.NAMESPACE}} -o wide

  logs:
    desc: Gateway ログ
    deps: [deps:kubectl]
    cmds:
      - kubectl logs -n {{.NAMESPACE}} -l app=openclaw-gateway --tail=100 -f

  logs-cognee:
    desc: Cognee Skills ログ
    deps: [deps:kubectl]
    cmds:
      - kubectl logs -n {{.NAMESPACE}} -l app=cognee-skills --tail=100 -f

  restart:
    desc: Gateway 再起動
    deps: [deps:kubectl]
    cmds:
      - kubectl rollout restart deployment/openclaw-gateway -n {{.NAMESPACE}}

  shell:
    desc: Gateway Pod にシェル接続
    deps: [deps:kubectl]
    cmds:
      - kubectl exec -it -n {{.NAMESPACE}} deployment/openclaw-gateway -- /bin/bash
```

- [ ] **Step 5: Update sandbox.yml**

```yaml
version: "3"

tasks:
  ps:
    desc: Sandbox コンテナ一覧
    deps: [deps:docker]
    cmds:
      - docker ps --filter "label=openclaw-sandbox" --format "table {{'{{'}}.ID{{'}}'}}\\t{{'{{'}}.Image{{'}}'}}\\t{{'{{'}}.Status{{'}}'}}\\t{{'{{'}}.Names{{'}}'}}"

  gc:
    desc: 停止した Sandbox コンテナを削除
    deps: [deps:docker]
    cmds:
      - docker container prune --filter "label=openclaw-sandbox" -f
```

- [ ] **Step 6: Update secrets.yml**

Add `deps:` to each task:

```yaml
version: "3"

tasks:
  connect-creds:
    desc: 1Password Connect クレデンシャルを K8s Secret として登録
    deps: [deps:kubectl]
    status:
      - kubectl get secret op-credentials -n {{.NAMESPACE}} 2>/dev/null
      - kubectl get secret onepassword-token -n {{.NAMESPACE}} 2>/dev/null
    preconditions:
      - sh: test -f "{{.OP_CREDENTIALS_FILE}}"
        msg: "1password-credentials.json が見つかりません。1Password Web UI の Connect Server セクションからダウンロードしてください。"
      - sh: test -n "{{.OP_CONNECT_TOKEN}}"
        msg: "OP_CONNECT_TOKEN を設定してください: task secrets:connect-creds OP_CONNECT_TOKEN=<token>"
    vars:
      OP_CREDENTIALS_FILE: '{{.OP_CREDENTIALS_FILE | default "base/secrets/1password-credentials.json"}}'
    cmds:
      - |
        kubectl create secret generic op-credentials \
          --namespace {{.NAMESPACE}} \
          --from-file=1password-credentials.json={{.OP_CREDENTIALS_FILE}} \
          --dry-run=client -o yaml | kubectl apply -f -
        kubectl create secret generic onepassword-token \
          --namespace {{.NAMESPACE}} \
          --from-literal=token='{{.OP_CONNECT_TOKEN}}' \
          --dry-run=client -o yaml | kubectl apply -f -
        echo "op-credentials + onepassword-token created in {{.NAMESPACE}}"

  eso:
    desc: External Secrets Operator を Helm でインストール
    deps: [deps:helm, deps:kubectl]
    status:
      - helm list -n external-secrets 2>/dev/null | grep -q external-secrets
    cmds:
      - helm repo add external-secrets https://charts.external-secrets.io
      - helm repo update external-secrets
      - |
        helm install external-secrets external-secrets/external-secrets \
          --namespace external-secrets \
          --create-namespace \
          --set installCRDs=true \
          --wait
      - echo "ESO installed in external-secrets namespace"

  connect:
    desc: 1Password Connect を Helm でインストール
    deps: [deps:helm, deps:kubectl]
    status:
      - helm list -n {{.NAMESPACE}} 2>/dev/null | grep -q onepassword-connect
    cmds:
      - helm repo add 1password https://1password.github.io/connect-helm-charts
      - helm repo update 1password
      - |
        helm install onepassword-connect 1password/connect \
          --namespace {{.NAMESPACE}} \
          --set connect.credentials_json_secret=op-credentials \
          --set connect.token_secret.name=onepassword-token \
          --set connect.token_secret.key=token \
          --wait
      - echo "1Password Connect installed in {{.NAMESPACE}}"

  status:
    desc: ExternalSecret の同期状態を確認
    deps: [deps:kubectl, deps:jq]
    cmds:
      - kubectl get externalsecret -n {{.NAMESPACE}}
      - |
        kubectl get secret openclaw-secrets -n {{.NAMESPACE}} -o json \
          | jq -r '.data | to_entries[] | "  \(.key): \(.value | length) chars (base64)"' \
          2>/dev/null || echo "  (secret not yet created)"
```

- [ ] **Step 7: Verify all tasks still work**

Run: `task --list`

Expected: All 20+ tasks listed without errors. deps tasks appear at top.

- [ ] **Step 8: Test deps integration**

Run: `task ops:status`

Expected: deps:kubectl resolves (up to date), then `kubectl get pods` runs.

- [ ] **Step 9: Commit**

```bash
git add tasks/cluster.yml tasks/build.yml tasks/deploy.yml tasks/ops.yml tasks/sandbox.yml tasks/secrets.yml
git commit -m "feat: add deps dependency to all task files"
```

---

### Task 5: テスト統合と最終検証

**Files:**

- Modify: `tasks/test.yml`

- [ ] **Step 1: Update test.yml to include deps tests**

```yaml
version: "3"

tasks:
  smoke:
    desc: スモークテスト
    cmds:
      - bash tests/smoke-test.sh

  deps:
    desc: deps テストを実行
    cmds:
      - bash tasks/deps/test-detect-os.sh
      - bash tasks/deps/test-install.sh
```

- [ ] **Step 2: Run deps tests**

Run: `task test:deps`

Expected: All tests PASS.

- [ ] **Step 3: Run full task list verification**

Run: `task --list 2>&1 | wc -l`

Expected: 22+ tasks (20 existing + deps:kind, deps:helm, deps:kubectl, deps:jq, deps:docker, deps:all, deps:test, test:deps).

- [ ] **Step 4: Test auto-install flow with helm**

Run: `task deps:helm`

Expected: If helm is not installed, winget installs it. If already installed, `Task is up to date`.

- [ ] **Step 5: Commit**

```bash
git add tasks/test.yml
git commit -m "feat: add deps test task"
```
