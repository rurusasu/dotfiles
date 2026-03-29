# OpenClaw Kind Migration Phase 2: ESO + 1Password Connect Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace manual `op read` secret creation with automated ESO + 1Password Connect synchronization, and simplify entrypoint.sh by removing secret fallback and config rendering logic.

**Architecture:** 1Password Connect runs as a pod in the Kind cluster, ESO polls it every 5 minutes and syncs secrets into a K8s Secret. An `envsubst` init container renders the openclaw.json config template (replacing `${VAR}` placeholders with secret values from env vars), writing the result to a shared emptyDir volume that the gateway container reads at startup. This eliminates the manual `task setup:secrets` step and the Docker-era secret fallback in entrypoint.sh.

**Tech Stack:** External Secrets Operator (Helm), 1Password Connect (Helm), Kustomize, alpine + envsubst (init container), shell (entrypoint.sh)

**Working directory:** `D:\ruru\openclaw-k8s`

---

## File Structure

| Action | File                                      | Responsibility                                                                                             |
| ------ | ----------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| Create | `base/secrets/secretstore.yaml`           | ESO → 1Password Connect connection definition                                                              |
| Create | `base/secrets/externalsecret.yaml`        | 1Password item → K8s Secret mapping (10 keys)                                                              |
| Modify | `base/kustomization.yaml`                 | Add secrets/ resources                                                                                     |
| Modify | `base/gateway/configmap.yaml`             | Replace hardcoded secrets with `${VAR}` placeholders                                                       |
| Modify | `base/gateway/deployment.yaml`            | Add envsubst init container, add secret env vars, update volume mounts                                     |
| Modify | `docker/gateway/entrypoint.sh`            | Remove Docker secret fallback (lines 1-37) and sed config rendering (lines 39-47)                          |
| Modify | `docker/gateway/tests/test-entrypoint.sh` | Remove Docker secret file tests (Suite 5 partial), add ESO-aware assertions                                |
| Modify | `Taskfile.yml`                            | Add `setup:eso`, `setup:connect`, `setup:connect-creds` tasks; update `setup` flow; remove `setup:secrets` |
| Modify | `tests/smoke-test.sh`                     | Add ExternalSecret sync status check                                                                       |
| Modify | `CLAUDE.md`                               | Document new setup flow                                                                                    |

---

## Task 1: Add Helm setup tasks to Taskfile

**Files:**

- Modify: `Taskfile.yml`

This task adds the Taskfile tasks for installing ESO and 1Password Connect via Helm. No cluster changes yet — just the task definitions.

- [ ] **Step 1: Add `setup:connect-creds` task**

This task creates the K8s secrets that 1Password Connect needs. The user must have already downloaded `1password-credentials.json` from the 1Password web UI.

Add after the `setup:secrets` task in `Taskfile.yml`:

```yaml
setup:connect-creds:
  desc: 1Password Connect クレデンシャルを K8s Secret として登録
  preconditions:
    - sh: test -f "{{.OP_CREDENTIALS_FILE}}"
      msg: "1password-credentials.json が見つかりません。1Password Web UI の Connect Server セクションからダウンロードしてください。"
    - sh: test -n "{{.OP_CONNECT_TOKEN}}"
      msg: "OP_CONNECT_TOKEN を設定してください: task setup:connect-creds OP_CONNECT_TOKEN=<token>"
  vars:
    OP_CREDENTIALS_FILE: '{{.OP_CREDENTIALS_FILE | default "1password-credentials.json"}}'
  cmds:
    - |
      kubectl create secret generic op-credentials \
        --namespace {{.NAMESPACE}} \
        --from-file=1password-credentials.json={{.OP_CREDENTIALS_FILE}} \
        --dry-run=client -o yaml | kubectl apply -f -
      kubectl create secret generic onepassword-token \
        --namespace {{.NAMESPACE}} \
        --from-literal=token={{.OP_CONNECT_TOKEN}} \
        --dry-run=client -o yaml | kubectl apply -f -
      echo "op-credentials + onepassword-token created in {{.NAMESPACE}}"
```

- [ ] **Step 2: Add `setup:eso` task**

```yaml
setup:eso:
  desc: External Secrets Operator を Helm でインストール
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
```

- [ ] **Step 3: Add `setup:connect` task**

```yaml
setup:connect:
  desc: 1Password Connect を Helm でインストール
  status:
    - helm list -n {{.NAMESPACE}} 2>/dev/null | grep -q onepassword-connect
  cmds:
    - helm repo add 1password https://1password.github.io/connect-helm-charts
    - helm repo update 1password
    - |
      helm install onepassword-connect 1password/connect \
        --namespace {{.NAMESPACE}} \
        --set-json='connect.credentials_json_secret="op-credentials"' \
        --set connect.token_secret.name=onepassword-token \
        --set connect.token_secret.key=token \
        --wait
    - echo "1Password Connect installed in {{.NAMESPACE}}"
```

- [ ] **Step 4: Update `setup` task to include ESO + Connect**

Replace the existing `setup` task:

```yaml
setup:
  desc: 初回フルセットアップ
  cmds:
    - task: cluster:create
    - task: setup:eso
    - task: setup:connect-creds
    - task: setup:connect
    - task: build
    - task: deploy
    - echo ""
    - echo "=== Setup complete ==="
    - echo "ESO will sync secrets from 1Password within 5 minutes."
    - echo "Run 'task status:secrets' to check sync status."
```

- [ ] **Step 5: Add `status:secrets` task and remove `setup:secrets`**

Add a status check task:

```yaml
  status:secrets:
    desc: ExternalSecret の同期状態を確認
    cmds:
      - kubectl get externalsecret -n {{.NAMESPACE}}
      - kubectl get secret openclaw-secrets -n {{.NAMESPACE}} -o jsonpath='{.data}' | python3 -c "import sys,json; d=json.load(sys.stdin); print('\n'.join(f'  {k}: {len(v)} chars (base64)' for k,v in sorted(d.items())))" 2>/dev/null || echo "  (secret not yet created)"
```

Remove the entire `setup:secrets` task block (lines 91-111 in current Taskfile.yml).

- [ ] **Step 6: Verify Taskfile syntax**

Run: `cd /d/ruru/openclaw-k8s && task --list`

Expected: All tasks listed without syntax errors. New tasks `setup:eso`, `setup:connect`, `setup:connect-creds`, `status:secrets` visible.

- [ ] **Step 7: Commit**

```bash
cd /d/ruru/openclaw-k8s
git add Taskfile.yml
git commit -m "feat: add ESO + 1Password Connect Helm setup tasks"
```

---

## Task 2: Create SecretStore and ExternalSecret manifests

**Files:**

- Create: `base/secrets/secretstore.yaml`
- Create: `base/secrets/externalsecret.yaml`
- Modify: `base/kustomization.yaml`

- [ ] **Step 1: Create `base/secrets/` directory**

```bash
mkdir -p base/secrets
```

- [ ] **Step 2: Create SecretStore manifest**

Write `base/secrets/secretstore.yaml`:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: onepassword
  namespace: openclaw
spec:
  provider:
    onepassword:
      connectHost: http://onepassword-connect:8080
      vaults:
        Personal:
          id: 1
      auth:
        secretRef:
          connectTokenSecretRef:
            name: onepassword-token
            key: token
```

Note: The vault ID (`1`) may need adjustment. After 1Password Connect is running, verify with:

```bash
kubectl exec -n openclaw deployment/onepassword-connect -- curl -s -H "Authorization: Bearer $(kubectl get secret -n openclaw onepassword-token -o jsonpath='{.data.token}' | base64 -d)" http://localhost:8080/v1/vaults | jq '.[].id'
```

- [ ] **Step 3: Create ExternalSecret manifest**

Write `base/secrets/externalsecret.yaml`:

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
    kind: SecretStore
  target:
    name: openclaw-secrets
    creationPolicy: Owner
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
        key: openclaw
        property: gateway token
    - secretKey: slack-bot-token
      remoteRef:
        key: SlackBot-OpenClaw
        property: bot_token
    - secretKey: slack-app-token
      remoteRef:
        key: SlackBot-OpenClaw
        property: app_level_token
    - secretKey: telegram-bot-token
      remoteRef:
        key: TelegramBot
        property: credential
    - secretKey: gemini-api-key
      remoteRef:
        key: OpenClawGeminiAPI
        property: credential
    - secretKey: exa-api-key
      remoteRef:
        key: OpenClawExaAPI
        property: credential
    - secretKey: tavily-api-key
      remoteRef:
        key: OpenClawTavilyAPI
        property: credential
    - secretKey: firecrawl-api-key
      remoteRef:
        key: OpenClawFirecrawlAPI
        property: credential
```

**Prerequisite:** Exa, Tavily, Firecrawl の API キーが 1Password に保存されていない場合、以下の名前で 1Password に登録する:

- `OpenClawExaAPI` (field: `credential`, value: `4d0b0528-265e-4d70-bf82-66ac865cbb74`)
- `OpenClawTavilyAPI` (field: `credential`, value: `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`)
- `OpenClawFirecrawlAPI` (field: `credential`, value: `fc-3ea0676224b6451aaf9440e565e2f5ae`)

- [ ] **Step 4: Update `base/kustomization.yaml`**

Add the secrets resources:

```yaml
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
  - secrets/secretstore.yaml
  - secrets/externalsecret.yaml
```

- [ ] **Step 5: Validate Kustomize build**

Run: `cd /d/ruru/openclaw-k8s && kubectl kustomize overlays/local/`

Expected: YAML output includes SecretStore and ExternalSecret resources. No errors.

- [ ] **Step 6: Commit**

```bash
cd /d/ruru/openclaw-k8s
git add base/secrets/ base/kustomization.yaml
git commit -m "feat: add SecretStore + ExternalSecret for 1Password Connect"
```

---

## Task 3: Migrate ConfigMap to use environment variable placeholders

**Files:**

- Modify: `base/gateway/configmap.yaml`

The ConfigMap currently contains hardcoded secrets (bot tokens, API keys, gateway auth token). Replace all secret values with `${VAR}` placeholders that `envsubst` will resolve at runtime via the init container.

- [ ] **Step 1: Replace hardcoded secrets with placeholders**

In `base/gateway/configmap.yaml`, replace the following values:

| Current value                                                                                                                  | Replacement             |
| ------------------------------------------------------------------------------------------------------------------------------ | ----------------------- |
| `@@GITHUB_TOKEN@@` (in sandbox.docker.env, 3 occurrences)                                                                      | `${GITHUB_TOKEN}`       |
| `@@XAI_API_KEY@@` (in sandbox.docker.env, 1 occurrence)                                                                        | `${XAI_API_KEY}`        |
| `<REDACTED>` (gateway.auth.token)              | `${GATEWAY_TOKEN}`      |
| `<REDACTED>` (channels.telegram.botToken)      | `${TELEGRAM_BOT_TOKEN}` |
| `<REDACTED>` (channels.slack.botToken)         | `${SLACK_BOT_TOKEN}`    |
| `<REDACTED>` (channels.slack.appToken)         | `${SLACK_APP_TOKEN}`    |
| `<REDACTED>` (plugins.entries.exa.config)      | `${EXA_API_KEY}`        |
| `<REDACTED>` (plugins.entries.tavily.config)   | `${TAVILY_API_KEY}`     |
| `<REDACTED>` (plugins.entries.firecrawl.config)| `${FIRECRAWL_API_KEY}`  |

After replacement, the relevant sections look like:

```json
"gateway": {
  "auth": {
    "mode": "token",
    "token": "${GATEWAY_TOKEN}"
  }
}
```

```json
"telegram": {
  "botToken": "${TELEGRAM_BOT_TOKEN}"
}
```

```json
"slack": {
  "botToken": "${SLACK_BOT_TOKEN}",
  "appToken": "${SLACK_APP_TOKEN}"
}
```

```json
"exa": {
  "enabled": true,
  "config": { "webSearch": { "apiKey": "${EXA_API_KEY}" } }
}
```

```json
"sandbox": {
  "docker": {
    "env": {
      "GITHUB_TOKEN": "${GITHUB_TOKEN}",
      "GH_TOKEN": "${GITHUB_TOKEN}",
      "XAI_API_KEY": "${XAI_API_KEY}",
      "GIT_CONFIG_KEY_0": "url.https://x-access-token:${GITHUB_TOKEN}@github.com/.insteadOf"
    }
  }
}
```

- [ ] **Step 2: Verify JSON validity**

Run: `cd /d/ruru/openclaw-k8s && kubectl kustomize overlays/local/ | python3 -c "import sys,yaml,json; docs=yaml.safe_load_all(sys.stdin); [json.loads(d['data']['openclaw.json']) for d in docs if d.get('kind')=='ConfigMap' and d['metadata']['name']=='openclaw-config']" && echo "JSON valid"`

Expected: "JSON valid" — the ConfigMap YAML is valid and the embedded JSON (with `${VAR}` strings) parses correctly.

- [ ] **Step 3: Commit**

```bash
cd /d/ruru/openclaw-k8s
git add base/gateway/configmap.yaml
git commit -m "feat: replace hardcoded secrets in ConfigMap with envsubst placeholders"
```

---

## Task 4: Add envsubst init container and update Deployment env vars

**Files:**

- Modify: `base/gateway/deployment.yaml`

Add an init container that runs `envsubst` to render the config template, and add all secret env vars to both the init container and the gateway container.

- [ ] **Step 1: Add init container and rendered-config volume**

Update `base/gateway/deployment.yaml`. Add the init container and the shared volume:

```yaml
initContainers:
  - name: render-config
    image: alpine:3.19
    command:
      - sh
      - -c
      - |
        apk add -q --no-cache gettext
        envsubst '${GITHUB_TOKEN} ${XAI_API_KEY} ${GATEWAY_TOKEN} ${TELEGRAM_BOT_TOKEN} ${SLACK_BOT_TOKEN} ${SLACK_APP_TOKEN} ${EXA_API_KEY} ${TAVILY_API_KEY} ${FIRECRAWL_API_KEY}' \
          < /config-tmpl/openclaw.json \
          > /config/openclaw.json
        echo "[init:render-config] config rendered ($(wc -c < /config/openclaw.json) bytes)"
    env:
      - name: GITHUB_TOKEN
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
      - name: GATEWAY_TOKEN
        valueFrom:
          secretKeyRef:
            name: openclaw-secrets
            key: gateway-token
      - name: TELEGRAM_BOT_TOKEN
        valueFrom:
          secretKeyRef:
            name: openclaw-secrets
            key: telegram-bot-token
      - name: SLACK_BOT_TOKEN
        valueFrom:
          secretKeyRef:
            name: openclaw-secrets
            key: slack-bot-token
      - name: SLACK_APP_TOKEN
        valueFrom:
          secretKeyRef:
            name: openclaw-secrets
            key: slack-app-token
      - name: EXA_API_KEY
        valueFrom:
          secretKeyRef:
            name: openclaw-secrets
            key: exa-api-key
            optional: true
      - name: TAVILY_API_KEY
        valueFrom:
          secretKeyRef:
            name: openclaw-secrets
            key: tavily-api-key
            optional: true
      - name: FIRECRAWL_API_KEY
        valueFrom:
          secretKeyRef:
            name: openclaw-secrets
            key: firecrawl-api-key
            optional: true
    volumeMounts:
      - name: openclaw-config
        mountPath: /config-tmpl
        readOnly: true
      - name: rendered-config
        mountPath: /config
```

- [ ] **Step 2: Update gateway container volume mounts**

Change the gateway container's config mount from the ConfigMap to the rendered config:

Old:

```yaml
- name: openclaw-config
  mountPath: /app/openclaw.json.tmpl
  subPath: openclaw.json
  readOnly: true
```

New:

```yaml
- name: rendered-config
  mountPath: /home/app/.openclaw/openclaw.json
  subPath: openclaw.json
  readOnly: true
```

This mounts the rendered (secrets-resolved) config directly at the final path, so entrypoint.sh no longer needs to render it.

- [ ] **Step 3: Add additional secret env vars to gateway container**

The gateway container already has `GITHUB_TOKEN`, `GH_TOKEN`, `XAI_API_KEY`. Add the remaining secrets that entrypoint.sh or the gateway process may need:

```yaml
- name: GEMINI_API_KEY
  valueFrom:
    secretKeyRef:
      name: openclaw-secrets
      key: gemini-api-key
      optional: true
```

No other secrets need to be env vars in the gateway container itself — the rest are only needed in the config (handled by init container).

- [ ] **Step 4: Add rendered-config volume**

In the `volumes` section, add:

```yaml
- name: rendered-config
  emptyDir:
    sizeLimit: 1Mi
```

- [ ] **Step 5: Validate Kustomize build**

Run: `cd /d/ruru/openclaw-k8s && kubectl kustomize overlays/local/ > /dev/null && echo "OK"`

Expected: "OK" — no syntax errors.

- [ ] **Step 6: Commit**

```bash
cd /d/ruru/openclaw-k8s
git add base/gateway/deployment.yaml
git commit -m "feat: add envsubst init container for config rendering"
```

---

## Task 5: Simplify entrypoint.sh

**Files:**

- Modify: `docker/gateway/entrypoint.sh`

Remove the Docker secret fallback logic and sed-based config rendering that are now handled by K8s (Secret env injection + init container).

- [ ] **Step 1: Remove Docker secret fallback for GITHUB_TOKEN (lines 1-18)**

Replace lines 1-18:

```sh
#!/bin/sh
set -eu

# --- GitHub token: prefer env var (K8s Secret), fall back to Docker secret file ---
if [ -z "${GITHUB_TOKEN:-}" ]; then
  _secret_file="/run/secrets/github_token"
  if [ -f "$_secret_file" ]; then
    GITHUB_TOKEN="$(cat "$_secret_file")"
    export GITHUB_TOKEN
  else
    echo "[FATAL] GITHUB_TOKEN not set and Docker secret not found: $_secret_file" >&2
    exit 1
  fi
fi
if [ -z "$GITHUB_TOKEN" ]; then
  echo "[FATAL] GitHub token is empty." >&2
  exit 1
fi
GH_TOKEN="$GITHUB_TOKEN"
export GH_TOKEN
```

With:

```sh
#!/bin/sh
set -eu

# --- Validate required env vars (injected by K8s Secret) ---
if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "[FATAL] GITHUB_TOKEN not set. Check openclaw-secrets K8s Secret." >&2
  exit 1
fi
GH_TOKEN="$GITHUB_TOKEN"
export GH_TOKEN
```

- [ ] **Step 2: Remove Docker secret fallback for XAI_API_KEY (lines 22-32)**

Remove entirely:

```sh
# --- xAI API key: prefer env var, fall back to Docker secret file (optional) ---
if [ -z "${XAI_API_KEY:-}" ]; then
  _xai_secret_file="/run/secrets/xai_api_key"
  if [ -f "$_xai_secret_file" ]; then
    _xai_key="$(cat "$_xai_secret_file")"
    if [ -n "$_xai_key" ]; then
      XAI_API_KEY="$_xai_key"
      export XAI_API_KEY
    fi
  fi
fi
```

XAI_API_KEY is optional and injected by K8s Secret env var. No fallback needed.

- [ ] **Step 3: Remove sed-based config rendering (lines 39-47)**

Remove entirely:

```sh
# --- Render config template: replace @@PLACEHOLDERS@@ with runtime secrets ---
_config_tmpl="/app/openclaw.json.tmpl"
_config_out="/home/app/.openclaw/openclaw.json"
if [ -f "$_config_tmpl" ]; then
  _config_tmp="${_config_out}.tmp.$$"
  sed -e "s|@@GITHUB_TOKEN@@|${GITHUB_TOKEN}|g" -e "s|@@XAI_API_KEY@@|${XAI_API_KEY:-}|g" "$_config_tmpl" >"$_config_tmp"
  mv "$_config_tmp" "$_config_out"
  echo "[entrypoint] config rendered to $_config_out"
fi
```

The init container now renders the config and mounts it at `/home/app/.openclaw/openclaw.json`.

- [ ] **Step 4: Update `_config_out` reference**

The variable `_config_out` is used later in the script (line 76: `if [ -f "$_config_out" ]; then`). Add a simple assignment near the top of the simplified section:

```sh
# Config is rendered by init container and mounted at this path.
_config_out="/home/app/.openclaw/openclaw.json"
```

- [ ] **Step 5: Update secret status log**

Replace the secret injection status log (lines 33-37):

```sh
# --- Log secret injection status ---
_gh_len=$(printf "%s" "$GITHUB_TOKEN" | wc -c)
_xai_status="not set"
if [ -n "${XAI_API_KEY:-}" ]; then _xai_status="ok ($(printf "%s" "$XAI_API_KEY" | wc -c) chars)"; fi
echo "[entrypoint] secrets: GITHUB_TOKEN=${_gh_len} chars, XAI_API_KEY=${_xai_status}"
```

With:

```sh
# --- Log secret injection status ---
_gh_len=$(printf "%s" "$GITHUB_TOKEN" | wc -c)
_xai_status="not set"
if [ -n "${XAI_API_KEY:-}" ]; then _xai_status="ok ($(printf "%s" "$XAI_API_KEY" | wc -c) chars)"; fi
echo "[entrypoint] secrets (K8s): GITHUB_TOKEN=${_gh_len} chars, XAI_API_KEY=${_xai_status}"
if [ -f "$_config_out" ]; then
  echo "[entrypoint] config: mounted by init container ($(wc -c < "$_config_out") bytes)"
else
  echo "[FATAL] config not found at $_config_out — init container may have failed" >&2
  exit 1
fi
```

- [ ] **Step 6: Verify entrypoint.sh syntax**

Run: `cd /d/ruru/openclaw-k8s && sh -n docker/gateway/entrypoint.sh && echo "syntax OK"`

Expected: "syntax OK"

- [ ] **Step 7: Commit**

```bash
cd /d/ruru/openclaw-k8s
git add docker/gateway/entrypoint.sh
git commit -m "refactor: simplify entrypoint.sh — remove Docker secret fallback and config rendering"
```

---

## Task 6: Update tests

**Files:**

- Modify: `docker/gateway/tests/test-entrypoint.sh`
- Modify: `tests/smoke-test.sh`

- [ ] **Step 1: Update test-entrypoint.sh Suite 5 (GitHub auth chain)**

In `docker/gateway/tests/test-entrypoint.sh`, the Docker secret tests in Suite 5 (lines 452-478) reference `/run/secrets/github_token` and `/run/secrets/xai_api_key`. These no longer exist in K8s. Replace them:

Remove:

```sh
  # --- Test: Docker secret (environment-based) ---
  assert "/run/secrets/github_token exists" \
    '[ -f /run/secrets/github_token ]'

  assert "/run/secrets/github_token is non-empty" \
    '[ -s /run/secrets/github_token ]'

  # --- Test: entrypoint exports GITHUB_TOKEN from secret ---
  # entrypoint.sh reads /run/secrets/github_token and exports GITHUB_TOKEN.
  # In docker exec sessions, entrypoint doesn't run, so simulate the read.
  _secret_token="$(cat /run/secrets/github_token 2>/dev/null || true)"
  assert "GITHUB_TOKEN matches Docker secret content" \
    '[ "${GITHUB_TOKEN:-}" = "$_secret_token" ] || [ -n "$_secret_token" ]'
```

Replace with:

```sh
  # --- Test: K8s Secret env injection ---
  assert "GITHUB_TOKEN is set via K8s Secret" \
    '[ -n "${GITHUB_TOKEN:-}" ]'

  assert "GH_TOKEN is set (alias for GITHUB_TOKEN)" \
    '[ -n "${GH_TOKEN:-}" ]'

  _secret_token="${GITHUB_TOKEN:-}"
```

- [ ] **Step 2: Remove Docker secret xAI test**

Remove:

```sh
  # --- Test: xAI API key secret ---
  if [ -f /run/secrets/xai_api_key ]; then
    assert "/run/secrets/xai_api_key exists" 'true'
    _xai_token="$(cat /run/secrets/xai_api_key 2>/dev/null || true)"
    if [ -n "$_xai_token" ]; then
      assert "XAI_API_KEY is set from secret" \
        '[ -n "${XAI_API_KEY:-}" ] || [ -n "$_xai_token" ]'
    else
      printf "  SKIP: xai_api_key secret is empty (optional)\n"
    fi
  else
    printf "  SKIP: /run/secrets/xai_api_key not found (optional)\n"
  fi
```

Replace with:

```sh
  # --- Test: XAI_API_KEY env injection (optional) ---
  if [ -n "${XAI_API_KEY:-}" ]; then
    assert "XAI_API_KEY is set via K8s Secret" 'true'
  else
    printf "  SKIP: XAI_API_KEY not set (optional)\n"
  fi
```

- [ ] **Step 3: Add config rendering test (init container output)**

Add to test-entrypoint.sh, after the auth chain section:

```sh
# ============================================================
# Test Suite 7: Config rendering (init container)
# ============================================================
_config="/home/app/.openclaw/openclaw.json"
if [ -f "$_config" ]; then
  printf "\n=== Config rendering ===\n"

  assert "config file exists" '[ -f "$_config" ]'

  assert "config is valid JSON" \
    'node -e "JSON.parse(require(\"fs\").readFileSync(\"$_config\",\"utf8\"))" 2>/dev/null'

  assert "config has no unresolved placeholders" \
    '! grep -qE "\\\$\\{[A-Z_]+\\}" "$_config"'

  assert "config gateway.auth.token is non-empty" \
    'node -e "const c=JSON.parse(require(\"fs\").readFileSync(\"$_config\",\"utf8\")); if(!c.gateway.auth.token||c.gateway.auth.token.startsWith(\"\\\${\"))process.exit(1)" 2>/dev/null'
else
  printf "\n=== Config rendering === (SKIPPED: not in container)\n"
fi
```

- [ ] **Step 4: Update smoke test to verify ExternalSecret sync**

Add to `tests/smoke-test.sh`, before the "Done" line:

```sh
echo "Checking ExternalSecret sync..."
ES_STATUS=$(kubectl get externalsecret -n $NAMESPACE openclaw-secrets -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
if [ "$ES_STATUS" = "True" ]; then
  echo "OK: ExternalSecret synced"
else
  echo "WARN: ExternalSecret not synced (status: ${ES_STATUS:-unknown})"
  echo "  This is expected on first deploy — ESO needs ~5 minutes to sync."
fi
```

- [ ] **Step 5: Verify test syntax**

Run: `cd /d/ruru/openclaw-k8s && sh -n docker/gateway/tests/test-entrypoint.sh && sh -n tests/smoke-test.sh && echo "syntax OK"`

Expected: "syntax OK"

- [ ] **Step 6: Run test locally (host-side tests only)**

Run: `cd /d/ruru/openclaw-k8s && sh docker/gateway/tests/test-entrypoint.sh`

Expected: All host-runnable tests pass. Container-only tests show "SKIPPED".

- [ ] **Step 7: Commit**

```bash
cd /d/ruru/openclaw-k8s
git add docker/gateway/tests/test-entrypoint.sh tests/smoke-test.sh
git commit -m "test: update tests for ESO-based secret management"
```

---

## Task 7: Update CLAUDE.md

**Files:**

- Modify: `CLAUDE.md`

- [ ] **Step 1: Update CLAUDE.md with new setup flow**

Replace the contents of `CLAUDE.md`:

````markdown
# openclaw-k8s: 開発ルール

## 概要

OpenClaw の Kind (Kubernetes in Docker) デプロイ構成を管理するリポジトリ。

## ディレクトリ構成

- `kind/`: Kind クラスタ定義
- `docker/`: Dockerfile, entrypoint.sh 等のビルド資材
- `base/`: Kustomize ベースマニフェスト
- `base/secrets/`: SecretStore + ExternalSecret (ESO)
- `overlays/`: 環境固有パッチ
- `tests/`: スモークテスト

## コマンド

```bash
task setup              # 初回フルセットアップ (cluster + ESO + Connect + build + deploy)
task build              # イメージビルド + Kind ロード
task deploy             # Kustomize デプロイ
task status             # Pod 状態確認
task status:secrets     # ExternalSecret 同期状態確認
task logs               # Gateway ログ
task restart            # Gateway 再起動
task cluster:create     # Kind クラスタ作成
task cluster:delete     # Kind クラスタ削除
```
````

## シークレット管理

- 1Password Connect + External Secrets Operator (ESO) で自動同期
- 手動の `op read` は不要 — ESO が 5 分ごとに 1Password から同期
- 初回セットアップ時のみ `1password-credentials.json` + Connect Token が必要
- ConfigMap の `${VAR}` プレースホルダーは init container (envsubst) が解決

## ルール

- シークレットを Git にコミットしない
- ConfigMap にシークレットの実値を書かない（`${VAR}` プレースホルダーを使う）
- マニフェスト変更後は `task deploy` で反映
- Docker イメージ変更後は `task build && task deploy` で反映

````

- [ ] **Step 2: Commit**

```bash
cd /d/ruru/openclaw-k8s
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for ESO-based secret management"
````

---

## Task 8: Integration test — full deploy cycle

**Files:** None (verification only)

This task verifies the entire Phase 2 setup end-to-end.

- [ ] **Step 1: Prerequisite — 1Password items exist**

Verify these items exist in 1Password (vault: Personal):

- `GitHubUsedOpenClawPAT` (field: `credential`)
- `xAI-Grok-Twitter` (field: `apikey`)
- `openclaw` (field: `gateway token`)
- `SlackBot-OpenClaw` (fields: `bot_token`, `app_level_token`)
- `TelegramBot` (field: `credential`)
- `OpenClawGeminiAPI` (field: `credential`)
- `OpenClawExaAPI` (field: `credential`)
- `OpenClawTavilyAPI` (field: `credential`)
- `OpenClawFirecrawlAPI` (field: `credential`)

If exa/tavily/firecrawl items are missing, create them in 1Password before proceeding.

- [ ] **Step 2: Prerequisite — Generate 1Password Connect credentials**

1. Open 1Password web UI → Integrations → Directory
2. Create a new "Connect Server" (or use existing)
3. Download `1password-credentials.json`
4. Copy the Connect Token
5. Place `1password-credentials.json` in the `openclaw-k8s` root directory

- [ ] **Step 3: Delete existing cluster for clean test**

Run: `cd /d/ruru/openclaw-k8s && task cluster:delete`

Expected: Cluster deleted (or "no cluster found").

- [ ] **Step 4: Run full setup**

Run: `cd /d/ruru/openclaw-k8s && task setup OP_CONNECT_TOKEN=<your-token>`

Expected output flow:

1. Kind cluster created
2. ESO installed in `external-secrets` namespace
3. 1Password Connect credentials registered
4. 1Password Connect installed
5. Docker images built and loaded
6. Kustomize deployed

- [ ] **Step 5: Wait for ESO sync**

Run: `cd /d/ruru/openclaw-k8s && task status:secrets`

If ExternalSecret shows `SecretSynced = False`, wait and retry (ESO polls every 5 minutes, first sync may take 1-2 minutes).

Expected: ExternalSecret status shows `SecretSynced = True`, all 10 secret keys listed.

- [ ] **Step 6: Verify pods are running**

Run: `cd /d/ruru/openclaw-k8s && task status`

Expected: All 3 pods (gateway, cognee-skills, falkordb) + onepassword-connect in Running state.

- [ ] **Step 7: Verify config rendering**

Run: `cd /d/ruru/openclaw-k8s && kubectl exec -n openclaw deployment/openclaw-gateway -- cat /home/app/.openclaw/openclaw.json | python3 -c "import sys,json; c=json.load(sys.stdin); assert not any(v for v in [c['gateway']['auth']['token'], c['channels']['telegram']['botToken']] if v.startswith('\${')); print('Config rendering OK: no unresolved placeholders')"`

Expected: "Config rendering OK: no unresolved placeholders"

- [ ] **Step 8: Run smoke test**

Run: `cd /d/ruru/openclaw-k8s && task test:smoke`

Expected: All checks pass, ExternalSecret synced.

- [ ] **Step 9: Run entrypoint tests inside container**

Run: `cd /d/ruru/openclaw-k8s && kubectl exec -n openclaw deployment/openclaw-gateway -- sh /app/tests/test-entrypoint.sh`

Expected: All tests pass (including new Suite 7: Config rendering).
