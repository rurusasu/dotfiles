# OpenClaw SLM Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace cognee-skills + FalkorDB with SuperLocalMemory + Ollama in the openclaw-k8s Kind cluster.

**Architecture:** Ollama Pod provides embedding/LLM for the cluster. SuperLocalMemory Pod runs as MCP server in Mode B (Ollama). Gateway connects via openclaw-mcp-bridge. skills_tools logic is rewritten as a sidecar script in the SLM container.

**Tech Stack:** SuperLocalMemory V3 (npm), Ollama (official Docker image), Kubernetes (Kind), Kustomize, Bash, Python 3

**Spec:** `docs/superpowers/specs/2026-03-29-openclaw-slm-migration-design.md`

**Working directory:** `D:\ruru\openclaw-k8s`

---

## File Structure

### New files

| Path                                              | Responsibility                                              |
| ------------------------------------------------- | ----------------------------------------------------------- |
| `base/ollama/deployment.yaml`                     | Ollama Pod (init container for model pull + main container) |
| `base/ollama/service.yaml`                        | ClusterIP service on port 11434                             |
| `base/ollama/pvc.yaml`                            | 10Gi PVC for model storage                                  |
| `base/superlocalmemory/deployment.yaml`           | SLM Pod (MCP server + skills_tools sidecar)                 |
| `base/superlocalmemory/service.yaml`              | ClusterIP service on port 3000                              |
| `base/superlocalmemory/pvc.yaml`                  | 5Gi PVC for SLM data                                        |
| `docker/superlocalmemory/Dockerfile`              | SLM image with skills_tools                                 |
| `docker/superlocalmemory/entrypoint.sh`           | SLM startup script                                          |
| `docker/superlocalmemory/skills_tools/health.py`  | Health scoring (migrated from cognee)                       |
| `docker/superlocalmemory/skills_tools/improve.py` | Skill improvement via Ollama LLM                            |
| `docker/superlocalmemory/skills_tools/amend.py`   | Skill file amendment (migrated)                             |

### Modified files

| Path                          | Change                                                                   |
| ----------------------------- | ------------------------------------------------------------------------ |
| `base/kustomization.yaml`     | Add ollama + superlocalmemory resources, remove cognee-skills + falkordb |
| `base/gateway/configmap.yaml` | MCP bridge: cognee-skills → superlocalmemory. Add memorySearch.ollama    |
| `base/cron/configmap.yaml`    | Rewrite cognee-daily-ingest → slm-daily-ingest                           |
| `Taskfile.yml`                | Add build:superlocalmemory task, remove build:cognee-skills              |
| `tests/smoke-test.sh`         | Replace cognee-skills/falkordb checks with ollama/slm checks             |

### Deleted files

| Path                                       | Reason                       |
| ------------------------------------------ | ---------------------------- |
| `base/cognee-skills/deployment.yaml`       | Replaced by superlocalmemory |
| `base/cognee-skills/service.yaml`          | Replaced by superlocalmemory |
| `base/cognee-skills/pvc.yaml`              | Replaced by slm-data         |
| `base/falkordb/deployment.yaml`            | No longer needed             |
| `base/falkordb/service.yaml`               | No longer needed             |
| `base/falkordb/pvc.yaml`                   | No longer needed             |
| `docker/cognee-skills/` (entire directory) | Replaced by superlocalmemory |

---

## Phase 1: Ollama Pod

### Task 1: Ollama Kubernetes Manifests

**Files:**

- Create: `base/ollama/pvc.yaml`
- Create: `base/ollama/service.yaml`
- Create: `base/ollama/deployment.yaml`

- [ ] **Step 1: Create PVC**

```yaml
# base/ollama/pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ollama-data
  namespace: openclaw
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```

- [ ] **Step 2: Create Service**

```yaml
# base/ollama/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: ollama
  namespace: openclaw
spec:
  selector:
    app: ollama
  ports:
    - port: 11434
      targetPort: 11434
```

- [ ] **Step 3: Create Deployment with init container for model pull**

```yaml
# base/ollama/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ollama
  namespace: openclaw
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: ollama
  template:
    metadata:
      labels:
        app: ollama
    spec:
      initContainers:
        - name: pull-models
          image: ollama/ollama:latest
          command:
            - sh
            - -c
            - |
              ollama serve &
              sleep 5
              ollama pull nomic-embed-text
              ollama pull qwen2.5:3b
              kill %1
          volumeMounts:
            - name: ollama-data
              mountPath: /root/.ollama
          resources:
            limits:
              memory: 4Gi
              cpu: "2"
      containers:
        - name: ollama
          image: ollama/ollama:latest
          ports:
            - containerPort: 11434
          volumeMounts:
            - name: ollama-data
              mountPath: /root/.ollama
          resources:
            limits:
              memory: 4Gi
              cpu: "2"
            requests:
              memory: 2Gi
              cpu: "1"
          livenessProbe:
            httpGet:
              path: /api/tags
              port: 11434
            initialDelaySeconds: 10
            periodSeconds: 30
          readinessProbe:
            httpGet:
              path: /api/tags
              port: 11434
            initialDelaySeconds: 5
            periodSeconds: 10
      volumes:
        - name: ollama-data
          persistentVolumeClaim:
            claimName: ollama-data
```

- [ ] **Step 4: Commit**

```bash
git add base/ollama/
git commit -m "feat: add Ollama deployment manifests"
```

---

### Task 2: Register Ollama in Kustomization and Deploy

**Files:**

- Modify: `base/kustomization.yaml`

- [ ] **Step 1: Add Ollama resources to kustomization.yaml**

Add these 3 lines after the existing resources (before cognee-skills lines):

```yaml
- ollama/pvc.yaml
- ollama/deployment.yaml
- ollama/service.yaml
```

- [ ] **Step 2: Apply and verify**

Run:

```bash
task deploy
kubectl get pods -n openclaw -l app=ollama -w
```

Expected: ollama pod starts, init container pulls models (may take 5-10 min first time), then main container reaches Ready.

- [ ] **Step 3: Test Ollama connectivity**

```bash
kubectl exec -n openclaw deploy/openclaw-gateway -- curl -sf http://ollama:11434/api/tags
```

Expected: JSON response listing `nomic-embed-text` and `qwen2.5:3b` models.

- [ ] **Step 4: Commit**

```bash
git add base/kustomization.yaml
git commit -m "feat: register Ollama in kustomization"
```

---

## Phase 2: SuperLocalMemory Pod

### Task 3: SLM Dockerfile and Entrypoint

**Files:**

- Create: `docker/superlocalmemory/Dockerfile`
- Create: `docker/superlocalmemory/entrypoint.sh`

- [ ] **Step 1: Create Dockerfile**

```dockerfile
# docker/superlocalmemory/Dockerfile
FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl python3 python3-pip git \
    && rm -rf /var/lib/apt/lists/*

# SuperLocalMemory V3
RUN npm install -g superlocalmemory

# Skills tools (improvement loop)
COPY skills_tools/ /app/skills_tools/
RUN pip3 install --break-system-packages requests

# Non-root user
RUN useradd -m -u 1000 app
USER app

WORKDIR /app
EXPOSE 3000

COPY --chown=app:app entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
```

- [ ] **Step 2: Create entrypoint.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Configure SLM for Mode B (Ollama)
export SLM_MODE="${SLM_MODE:-b}"
export OLLAMA_HOST="${OLLAMA_HOST:-http://ollama:11434}"
export SLM_DATA_DIR="${SLM_DATA_DIR:-/data}"

# Initialize SLM if first run
if [ ! -f "$SLM_DATA_DIR/memory.db" ]; then
  echo "[SLM] First run — initializing..."
  slm setup --mode "$SLM_MODE" --data-dir "$SLM_DATA_DIR" --non-interactive 2>/dev/null || true
fi

# Create openclaw profile if not exists
slm profile create openclaw 2>/dev/null || true
slm profile switch openclaw 2>/dev/null || true

echo "[SLM] Starting MCP server on port 3000 (Mode $SLM_MODE)..."
exec slm mcp --port 3000 --host 0.0.0.0
```

- [ ] **Step 3: Commit**

```bash
git add docker/superlocalmemory/Dockerfile docker/superlocalmemory/entrypoint.sh
git commit -m "feat: add SuperLocalMemory Dockerfile and entrypoint"
```

---

### Task 4: Skills Tools Migration

**Files:**

- Create: `docker/superlocalmemory/skills_tools/health.py`
- Create: `docker/superlocalmemory/skills_tools/improve.py`
- Create: `docker/superlocalmemory/skills_tools/amend.py`

- [ ] **Step 1: Create health.py (pure logic, no external deps)**

```python
#!/usr/bin/env python3
"""Skill health scoring — migrated from cognee-skills.

Pure calculation, no external dependencies.
"""

import os

WINDOW = int(os.environ.get("SKILL_HEALTH_WINDOW", "20"))
THRESHOLD = float(os.environ.get("SKILL_HEALTH_THRESHOLD", "0.7"))
PENALTY = float(os.environ.get("SKILL_CORRECTION_PENALTY", "0.05"))


def calculate_health_score(
    executions: list[dict],
    correction_count: int = 0,
) -> float:
    """Calculate health score from recent executions.

    Args:
        executions: List of dicts with boolean 'success' field.
        correction_count: Number of user corrections.

    Returns:
        Score clamped to [0.0, 1.0].
    """
    recent = executions[-WINDOW:]
    if not recent:
        return 1.0
    successes = sum(1 for e in recent if e.get("success", False))
    rate = successes / len(recent)
    score = rate - (correction_count * PENALTY)
    return max(0.0, min(1.0, score))


def needs_improvement(score: float) -> bool:
    return score < THRESHOLD
```

- [ ] **Step 2: Create improve.py (generates improvement via Ollama)**

```python
#!/usr/bin/env python3
"""Skill improvement proposals via Ollama LLM."""

import json
import os
import requests

OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "http://ollama:11434")
OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "qwen2.5:3b")


def generate_improvement(
    skill_name: str,
    skill_content: str,
    recent_failures: list[dict],
) -> dict:
    """Generate a skill improvement proposal using Ollama.

    Args:
        skill_name: Name of the skill.
        skill_content: Current SKILL.md content.
        recent_failures: List of recent failure records.

    Returns:
        Dict with 'diff' (unified diff string) and 'rationale'.
    """
    failures_text = "\n".join(
        f"- {f.get('error', 'unknown error')} (task: {f.get('task_description', 'N/A')})"
        for f in recent_failures[:10]
    )

    prompt = f"""You are a skill improvement assistant. Analyze the following SKILL.md
and its recent failures, then propose a minimal improvement as a unified diff.

## Current SKILL.md for "{skill_name}"
```

{skill_content}

```

## Recent Failures
{failures_text}

## Instructions
1. Identify the root cause pattern in the failures.
2. Propose the smallest change to SKILL.md that addresses it.
3. Return ONLY valid JSON with two fields:
   - "diff": a unified diff string
   - "rationale": one sentence explaining the change
"""

    resp = requests.post(
        f"{OLLAMA_HOST}/api/generate",
        json={
            "model": OLLAMA_MODEL,
            "prompt": prompt,
            "stream": False,
            "format": "json",
        },
        timeout=120,
    )
    resp.raise_for_status()
    text = resp.json().get("response", "{}")

    try:
        result = json.loads(text)
        return {
            "diff": result.get("diff", ""),
            "rationale": result.get("rationale", "No rationale provided"),
        }
    except json.JSONDecodeError:
        return {"diff": "", "rationale": f"LLM returned invalid JSON: {text[:200]}"}
```

- [ ] **Step 3: Create amend.py (file write logic, migrated from cognee)**

```python
#!/usr/bin/env python3
"""Skill amendment — applies proposed changes to SKILL.md files."""

import hashlib
import json
import os
from datetime import datetime, timezone


def amend_skill(
    skill_name: str,
    proposed_content: str,
    rationale: str,
    skills_dir: str = "/app/data/skills",
    versions_dir: str = "/app/data/skill_versions",
) -> dict:
    """Apply an improvement proposal to a skill's SKILL.md.

    Args:
        skill_name: Name of the skill directory.
        proposed_content: New SKILL.md content.
        rationale: Why this change was made.
        skills_dir: Base directory for skills.
        versions_dir: Directory to store version backups.

    Returns:
        Dict with 'success', 'message', and 'version_id'.
    """
    skill_path = os.path.join(skills_dir, skill_name, "SKILL.md")
    if not os.path.exists(skill_path):
        return {"success": False, "message": f"Skill not found: {skill_path}"}

    # Read current content and create backup
    with open(skill_path, "r") as f:
        current_content = f.read()

    content_hash = hashlib.sha256(current_content.encode()).hexdigest()[:12]
    version_id = f"{skill_name}-{content_hash}-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S')}"

    os.makedirs(versions_dir, exist_ok=True)
    version_record = {
        "version_id": version_id,
        "skill_name": skill_name,
        "content_hash": content_hash,
        "rationale": rationale,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    version_path = os.path.join(versions_dir, f"{version_id}.json")
    with open(version_path, "w") as f:
        json.dump(version_record, f, indent=2)

    # Apply the amendment
    try:
        with open(skill_path, "w") as f:
            f.write(proposed_content)
        return {"success": True, "message": f"Amended {skill_name}", "version_id": version_id}
    except OSError as e:
        return {"success": False, "message": str(e), "version_id": version_id}
```

- [ ] **Step 4: Commit**

```bash
git add docker/superlocalmemory/skills_tools/
git commit -m "feat: add skills_tools for SLM (health, improve, amend)"
```

---

### Task 5: SLM Kubernetes Manifests

**Files:**

- Create: `base/superlocalmemory/pvc.yaml`
- Create: `base/superlocalmemory/service.yaml`
- Create: `base/superlocalmemory/deployment.yaml`

- [ ] **Step 1: Create PVC**

```yaml
# base/superlocalmemory/pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: slm-data
  namespace: openclaw
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
```

- [ ] **Step 2: Create Service**

```yaml
# base/superlocalmemory/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: superlocalmemory
  namespace: openclaw
spec:
  selector:
    app: superlocalmemory
  ports:
    - port: 3000
      targetPort: 3000
```

- [ ] **Step 3: Create Deployment**

```yaml
# base/superlocalmemory/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: superlocalmemory
  namespace: openclaw
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: superlocalmemory
  template:
    metadata:
      labels:
        app: superlocalmemory
    spec:
      containers:
        - name: superlocalmemory
          image: local/superlocalmemory:dev
          imagePullPolicy: Never
          ports:
            - containerPort: 3000
          env:
            - name: SLM_MODE
              value: "b"
            - name: OLLAMA_HOST
              value: "http://ollama:11434"
            - name: SLM_DATA_DIR
              value: "/data"
            - name: SKILL_HEALTH_WINDOW
              value: "20"
            - name: SKILL_HEALTH_THRESHOLD
              value: "0.7"
            - name: SKILL_CORRECTION_PENALTY
              value: "0.05"
            - name: OLLAMA_MODEL
              value: "qwen2.5:3b"
          volumeMounts:
            - name: slm-data
              mountPath: /data
            - name: openclaw-home
              mountPath: /openclaw-sessions
              subPath: agents
              readOnly: true
            - name: openclaw-data
              mountPath: /app/data
          readinessProbe:
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 10
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 30
            periodSeconds: 30
          resources:
            limits:
              memory: 1Gi
              cpu: "1"
            requests:
              memory: 512Mi
              cpu: "0.5"
          securityContext:
            runAsUser: 1000
            runAsGroup: 1000
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
      volumes:
        - name: slm-data
          persistentVolumeClaim:
            claimName: slm-data
        - name: openclaw-home
          persistentVolumeClaim:
            claimName: openclaw-home
        - name: openclaw-data
          persistentVolumeClaim:
            claimName: openclaw-data
```

- [ ] **Step 4: Commit**

```bash
git add base/superlocalmemory/
git commit -m "feat: add SuperLocalMemory deployment manifests"
```

---

### Task 6: Taskfile Build Task

**Files:**

- Modify: `Taskfile.yml`

- [ ] **Step 1: Replace build:cognee-skills with build:superlocalmemory**

Find the `build:cognee-skills` task and replace it with:

```yaml
build:superlocalmemory:
  desc: Build SuperLocalMemory image and load into Kind
  cmds:
    - docker build -t local/superlocalmemory:dev docker/superlocalmemory/
    - kind load docker-image local/superlocalmemory:dev --name {{.CLUSTER_NAME}}
```

- [ ] **Step 2: Update the `build` task deps**

Replace `build:cognee-skills` with `build:superlocalmemory` in the `build` task's `deps` list. Remove `build:cognee-skills` entirely.

Note: No `build:ollama` task needed since it uses the official `ollama/ollama` image directly.

- [ ] **Step 3: Verify build works**

Run:

```bash
task build:superlocalmemory
```

Expected: Docker image builds successfully, loads into Kind.

- [ ] **Step 4: Commit**

```bash
git add Taskfile.yml
git commit -m "feat: replace build:cognee-skills with build:superlocalmemory in Taskfile"
```

---

## Phase 3: Gateway Configuration Update

### Task 7: Update Gateway ConfigMap

**Files:**

- Modify: `base/gateway/configmap.yaml`

- [ ] **Step 1: Replace MCP bridge cognee-skills entry**

In the `openclaw-mcp-bridge` → `servers` section, replace:

```json
"cognee-skills": {
  "transport": "streamable-http",
  "url": "http://cognee-skills:8000/mcp",
  "description": "Cognee MCP skills"
}
```

with:

```json
"superlocalmemory": {
  "transport": "streamable-http",
  "url": "http://superlocalmemory:3000/mcp",
  "description": "SuperLocalMemory MCP (memory + skill improvement)"
}
```

- [ ] **Step 2: Add memorySearch Ollama provider**

In the `memorySearch` section (or add it if not present), add:

```json
"memorySearch": {
  "enabled": true,
  "provider": "ollama",
  "model": "nomic-embed-text",
  "ollama": {
    "baseUrl": "http://ollama:11434"
  },
  "sources": ["memory", "sessions"],
  "experimental": {
    "sessionMemory": true
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add base/gateway/configmap.yaml
git commit -m "feat: update gateway MCP bridge to SuperLocalMemory + Ollama embeddings"
```

---

### Task 8: Update Cron ConfigMap

**Files:**

- Modify: `base/cron/configmap.yaml`

- [ ] **Step 1: Replace cognee-daily-ingest with slm-daily-ingest**

Replace the `cognee-daily-ingest` job entry with:

```json
{
  "id": "slm-daily-ingest",
  "schedule": "50 23 * * *",
  "timezone": "Asia/Tokyo",
  "agent": "main",
  "delivery": "silent",
  "task": "Daily memory ingest and skill improvement:\n1. Find session JSONL files: find /home/app/.openclaw -name '*.session.jsonl' -mtime -1\n2. For each session file, use superlocalmemory_remember to store key facts and decisions.\n3. Use superlocalmemory_recall to search for: 'user complaint', 'error', 'skill failure', 'feedback'.\n4. For each skill in /app/data/skills/*/SKILL.md:\n   a. Check recent execution logs via superlocalmemory_recall with query 'skill:{skill_name} execution'\n   b. If failure rate is high, use superlocalmemory_recall to find patterns\n   c. Propose minimal improvements based on failure patterns\n5. Only report if skills were improved or errors occurred."
}
```

- [ ] **Step 2: Commit**

```bash
git add base/cron/configmap.yaml
git commit -m "feat: replace cognee-daily-ingest with slm-daily-ingest cron job"
```

---

## Phase 4: Remove cognee-skills + FalkorDB

### Task 9: Update Kustomization and Delete Old Resources

**Files:**

- Modify: `base/kustomization.yaml`
- Delete: `base/cognee-skills/deployment.yaml`
- Delete: `base/cognee-skills/service.yaml`
- Delete: `base/cognee-skills/pvc.yaml`
- Delete: `base/falkordb/deployment.yaml`
- Delete: `base/falkordb/service.yaml`
- Delete: `base/falkordb/pvc.yaml`

- [ ] **Step 1: Update kustomization.yaml**

Remove these lines:

```yaml
- cognee-skills/pvc.yaml
- cognee-skills/deployment.yaml
- cognee-skills/service.yaml
- falkordb/pvc.yaml
- falkordb/deployment.yaml
- falkordb/service.yaml
```

Add these lines (if not already added in Task 2):

```yaml
- ollama/pvc.yaml
- ollama/deployment.yaml
- ollama/service.yaml
- superlocalmemory/pvc.yaml
- superlocalmemory/deployment.yaml
- superlocalmemory/service.yaml
```

Final resources list should be:

```yaml
resources:
  - namespace.yaml
  - gateway/pvc.yaml
  - gateway/configmap.yaml
  - gateway/deployment.yaml
  - gateway/service.yaml
  - ollama/pvc.yaml
  - ollama/deployment.yaml
  - ollama/service.yaml
  - superlocalmemory/pvc.yaml
  - superlocalmemory/deployment.yaml
  - superlocalmemory/service.yaml
  - cron/configmap.yaml
  - secrets/secretstore.yaml
  - secrets/externalsecret.yaml
```

- [ ] **Step 2: Delete cognee-skills and falkordb directories**

```bash
rm -rf base/cognee-skills/
rm -rf base/falkordb/
```

- [ ] **Step 3: Delete docker/cognee-skills directory**

```bash
rm -rf docker/cognee-skills/
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: remove cognee-skills and FalkorDB manifests and Docker files"
```

---

## Phase 5: Tests and Verification

### Task 10: Update Smoke Tests

**Files:**

- Modify: `tests/smoke-test.sh`

- [ ] **Step 1: Replace cognee-skills and FalkorDB checks**

Replace the FalkorDB readiness check:

```bash
echo "--- Check 5: FalkorDB pod ready ---"
kubectl wait --for=condition=ready pod -l app=falkordb -n openclaw --timeout=30s
echo "PASS: FalkorDB pod ready"
```

with:

```bash
echo "--- Check 5: Ollama pod ready ---"
kubectl wait --for=condition=ready pod -l app=ollama -n openclaw --timeout=300s
echo "PASS: Ollama pod ready"
```

Replace the cognee-skills readiness check:

```bash
echo "--- Check 6: cognee-skills pod ready ---"
if kubectl wait --for=condition=ready pod -l app=cognee-skills -n openclaw --timeout=60s 2>/dev/null; then
  echo "PASS: cognee-skills pod ready"
else
  echo "WARN: cognee-skills pod not ready (may need Gemini API key)"
fi
```

with:

```bash
echo "--- Check 6: SuperLocalMemory pod ready ---"
kubectl wait --for=condition=ready pod -l app=superlocalmemory -n openclaw --timeout=120s
echo "PASS: SuperLocalMemory pod ready"
```

- [ ] **Step 2: Add Ollama model verification check**

After Check 6, add:

```bash
echo "--- Check 7: Ollama models available ---"
MODELS=$(kubectl exec -n openclaw deploy/ollama -- ollama list 2>/dev/null || echo "")
if echo "$MODELS" | grep -q "nomic-embed-text"; then
  echo "PASS: nomic-embed-text model available"
else
  echo "WARN: nomic-embed-text model not yet pulled"
fi
if echo "$MODELS" | grep -q "qwen2.5:3b"; then
  echo "PASS: qwen2.5:3b model available"
else
  echo "WARN: qwen2.5:3b model not yet pulled"
fi
```

- [ ] **Step 3: Add MCP connectivity check**

```bash
echo "--- Check 8: SLM MCP endpoint reachable from gateway ---"
if kubectl exec -n openclaw deploy/openclaw-gateway -- curl -sf --max-time 5 http://superlocalmemory:3000/health >/dev/null 2>&1; then
  echo "PASS: SLM MCP reachable from gateway"
else
  echo "WARN: SLM MCP not reachable from gateway"
fi
```

- [ ] **Step 4: Commit**

```bash
git add tests/smoke-test.sh
git commit -m "feat: update smoke tests for Ollama + SLM"
```

---

### Task 11: Full Deploy and Verification

**Files:** None (operational verification)

- [ ] **Step 1: Full rebuild and deploy**

```bash
task build:superlocalmemory
task deploy
```

- [ ] **Step 2: Verify all pods are running**

```bash
kubectl get pods -n openclaw
```

Expected output (4 pods, all Running):

```
NAME                                READY   STATUS    RESTARTS
ollama-xxx                          1/1     Running   0
openclaw-gateway-xxx                1/1     Running   0
superlocalmemory-xxx                1/1     Running   0
```

cognee-skills and falkordb should NOT appear.

- [ ] **Step 3: Run smoke tests**

```bash
task test:smoke
```

Expected: All checks PASS (Checks 1-8).

- [ ] **Step 4: Test SLM MCP tools from gateway**

```bash
kubectl exec -n openclaw deploy/openclaw-gateway -- curl -sf \
  -X POST http://superlocalmemory:3000/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":1}'
```

Expected: JSON response listing SLM's MCP tools (remember, recall, forget, trace, observe, etc.).

- [ ] **Step 5: Test Ollama from gateway**

```bash
kubectl exec -n openclaw deploy/openclaw-gateway -- curl -sf \
  http://ollama:11434/api/embeddings \
  -d '{"model":"nomic-embed-text","prompt":"test"}'
```

Expected: JSON response with embedding vector.

- [ ] **Step 6: Update CLAUDE.md if needed**

If quick commands or architecture references changed, update `CLAUDE.md` in openclaw-k8s.

- [ ] **Step 7: Final commit**

```bash
git add -A
git commit -m "feat: complete SLM migration — verified all pods and MCP connectivity"
```
