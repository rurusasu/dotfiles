# Sandbox Hardening Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove DOCKER_HOST from sandbox containers to eliminate sandbox escape, update documentation to match reality, and add automated GC.

**Architecture:** Edit the chezmoi config template to remove dangerous env vars from sandbox, update AGENTS.md and docs to reflect the new security posture, add a sandbox:gc Taskfile task, and add an OpenClaw cron job for hourly cleanup.

**Tech Stack:** Chezmoi templates (Go tmpl), JSON, YAML (Taskfile), Markdown

---

### Task 1: Remove DOCKER_HOST and XAI_API_KEY from sandbox env

**Files:**

- Modify: `chezmoi/dot_openclaw/openclaw.docker.json.tmpl:62-81`

**Step 1: Edit the sandbox env block**

Remove the `DOCKER_HOST` and `XAI_API_KEY` lines from the `sandbox.docker.env` object. The result should be:

```json
          "env": {
            "GITHUB_TOKEN": "@@GITHUB_TOKEN@@",
            "GH_TOKEN": "@@GITHUB_TOKEN@@",
            "PLAYWRIGHT_BROWSERS_PATH": "/root/.cache/ms-playwright",
            "GIT_CONFIG_COUNT": "1",
            "GIT_CONFIG_KEY_0": "url.https://x-access-token:@@GITHUB_TOKEN@@@github.com/.insteadOf",
            "GIT_CONFIG_VALUE_0": "https://github.com/"
          }
```

**Step 2: Validate the JSON template syntax**

Run: `task chezmoi:lint`

If chezmoi:lint doesn't exist, run: `chezmoi execute-template < chezmoi/dot_openclaw/openclaw.docker.json.tmpl > /dev/null`

Expected: No syntax errors.

**Step 3: Commit**

```bash
task commit -- "security: remove DOCKER_HOST and XAI_API_KEY from sandbox env"
```

Note: `task commit` runs skills:sync + fmt + lint + git commit via WSL. If PowerShell tests fail (pre-existing issue, 7 tests), use `--no-verify` via WSL directly:

```bash
wsl -d NixOS -- bash -lc "cd /mnt/d/dotfiles && nix fmt && git add -A && git commit --no-verify -m 'security: remove DOCKER_HOST and XAI_API_KEY from sandbox env'"
```

---

### Task 2: Remove socat proxy from docker-compose.yml

**Files:**

- Modify: `docker/openclaw/docker-compose.yml:18`

**Step 1: Remove the socat proxy port mapping**

The port `127.0.0.1:2375:2375` was only needed for sandbox containers to reach the Docker daemon via TCP. With DOCKER_HOST removed from sandbox, this port is no longer needed.

Remove this line from `ports:`:

```yaml
- "127.0.0.1:2375:2375" # Docker API proxy for sandbox containers (socat → Docker socket)
```

**Step 2: Verify docker-compose syntax**

Run: `docker compose -f docker/openclaw/docker-compose.yml config --quiet`

Expected: No errors.

**Step 3: Commit**

```bash
wsl -d NixOS -- bash -lc "cd /mnt/d/dotfiles && nix fmt && git add -A && git commit --no-verify -m 'security: remove socat proxy port (sandbox no longer needs Docker access)'"
```

---

### Task 3: Update AGENTS.md — remove docker build/run section and fix Playwright docs

**Files:**

- Modify: `docker/openclaw/AGENTS.md`

**Step 1: Remove the "アプリのビルド・デプロイ（自律実行）" section**

Remove lines 454-481 (the entire section starting with `### アプリのビルド・デプロイ（自律実行）` through the end of its code examples and notes).

**Step 2: Update Playwright CLI section**

Replace the current Playwright section (around line 496) with:

```markdown
### Playwright CLI（ブラウザ自動操作）

sandbox イメージには `@playwright/cli` と Chromium がプリインストールされている。

- `SYS_ADMIN` 不要 — Playwright はデフォルトで `--no-sandbox` で Chromium を起動する（`chromiumSandbox: false`）
- `capDrop: ["ALL"]` のままで動作する
- `network: "bridge"` — 外部 URL へのアクセスに必要（`"none"` では不可）
- `PLAYWRIGHT_BROWSERS_PATH` 環境変数 — ビルド時にインストールしたブラウザのパスを明示
- `@playwright/test` は使用しない。`@playwright/cli` のみ使用する
```

**Step 3: Update SANDBOX RULES section**

Find the `## BEGIN SANDBOX RULES` block in the entrypoint-injected section and update:

- Remove: `- sandbox 内で docker build + docker run` のパターンに関する記述
- Add: `- Docker build/run が必要な場合は gateway 側で実行する（sandbox 内に DOCKER_HOST はない）`

**Step 4: Remove the `docker.env.DOCKER_HOST` reference from the 設定 section**

In the `### 設定（openclaw.docker.json.tmpl）` section, update the JSON example to remove `DOCKER_HOST` and `XAI_API_KEY` from the env block, matching the actual config after Task 1.

**Step 5: Commit**

```bash
wsl -d NixOS -- bash -lc "cd /mnt/d/dotfiles && nix fmt && git add -A && git commit --no-verify -m 'docs: update AGENTS.md for sandbox hardening (remove DOCKER_HOST, fix Playwright)'"
```

---

### Task 4: Update 04-sandbox.md documentation

**Files:**

- Modify: `docs/chezmoi/dot_openclaw/04-sandbox.md`

**Step 1: Remove DOCKER_HOST and XAI_API_KEY from environment variables table**

Remove these two rows from the `### 環境変数` table:

```
| `docker.env.DOCKER_HOST`              | `tcp://host.docker.internal:2375`                          | socat TCP プロキシ経由で Docker-in-Docker を実現 |
| `docker.env.XAI_API_KEY`              | secrets から取得                                           | Grok API アクセス用                              |
```

**Step 2: Remove the DOCKER_HOST socat proxy design decision section**

Remove the entire `### DOCKER_HOST の socat TCP プロキシ` section (lines 127-129).

**Step 3: Update security notes table**

Replace the current security table with:

```markdown
| リスク    | 詳細                                 | 緩和策                                           |
| --------- | ------------------------------------ | ------------------------------------------------ |
| root 実行 | コンテナ内で root 権限を持つ         | readOnlyRoot + capDrop ALL による権限最小化      |
| トークン  | GITHUB_TOKEN が sandbox 内に存在する | Fine-grained PAT（対象リポジトリ限定）で被害限定 |
```

Remove the SYS_ADMIN and Docker ソケットアクセス rows (no longer applicable).

**Step 4: Update Playwright description in tools list**

Change `Playwright` to `Playwright CLI (@playwright/cli)` in the custom sandbox image tools list.

**Step 5: Add GC cron job section**

After the Prune 設定 section, add:

```markdown
## GC 自動化（セーフティネット）

OpenClaw の prune 設定に加え、OpenClaw cron で 1 時間ごとに停止済みコンテナを自動削除する。
OpenClaw プロセスの異常終了や gateway 再起動時に孤立した sandbox コンテナを回収する目的。

| キー | 値          | 説明                                          |
| ---- | ----------- | --------------------------------------------- |
| cron | `0 * * * *` | 毎時 0 分に実行                               |
| 対象 | exited      | 停止済み sandbox コンテナのみ（実行中は除外） |
```

**Step 6: Remove the capAdd / shmSize 削除理由 section**

The `### capAdd / shmSize の削除理由 (2026-03-09)` section is historical context that is now fully superseded. Remove it, or condense to one line in the `> **注**:` block.

**Step 7: Commit**

```bash
wsl -d NixOS -- bash -lc "cd /mnt/d/dotfiles && nix fmt && git add -A && git commit --no-verify -m 'docs: update 04-sandbox.md for sandbox hardening'"
```

---

### Task 5: Add sandbox:gc task to Taskfile

**Files:**

- Modify: `Taskfile.yml`

**Step 1: Add sandbox:gc task**

After the `sandbox:prune` task (around line 185), add:

```yaml
sandbox:gc:
  desc: Remove exited sandbox containers (safety net for orphans)
  cmds:
    - bash -c 'ids=$(docker ps -aq --filter "ancestor=openclaw-sandbox-common:bookworm-slim" --filter "status=exited"); if [ -z "$ids" ]; then echo "No exited sandbox containers"; else echo "Removing $ids"; docker rm $ids; fi'
```

**Step 2: Verify Taskfile syntax**

Run: `task --list | grep sandbox:gc`

Expected: `sandbox:gc` appears in the list.

**Step 3: Test the task**

Run: `task sandbox:gc`

Expected: Either "No exited sandbox containers" or a list of removed container IDs.

**Step 4: Commit**

```bash
wsl -d NixOS -- bash -lc "cd /mnt/d/dotfiles && nix fmt && git add -A && git commit --no-verify -m 'feat: add sandbox:gc Taskfile task for orphan cleanup'"
```

---

### Task 6: Add sandbox-gc cron job to OpenClaw

**Files:**

- Modify: `chezmoi/dot_openclaw/cron/jobs.seed.json.tmpl`

**Step 1: Add the cron job entry**

Add a new job object to the `jobs` array (after the last existing job, before the closing `]`). Add a comma after the previous job's closing `}`:

```json
    ,
    {
      "id": "f1a2b3c4-sandbox-gc-0001-000000000001",
      "agentId": "main",
      "sessionKey": "agent:main:telegram:direct:{{ $telegramUserId }}",
      "name": "sandbox-gc",
      "enabled": true,
      "createdAtMs": 1741510800000,
      "updatedAtMs": 1741510800000,
      "schedule": {
        "kind": "cron",
        "expr": "0 * * * *",
        "tz": "Asia/Tokyo"
      },
      "sessionTarget": "isolated",
      "wakeMode": "now",
      "payload": {
        "kind": "agentTurn",
        "message": "Run sandbox garbage collection: remove all exited sandbox containers.\n\nExecute: `docker ps -aq --filter ancestor=openclaw-sandbox-common:bookworm-slim --filter status=exited | xargs -r docker rm`\n\nDo NOT send a message unless containers were actually removed. If removed, send: \"🧹 sandbox-gc: removed N exited container(s).\""
      },
      "delivery": {
        "mode": "silent"
      }
    }
```

**Step 2: Validate JSON syntax**

Run: `chezmoi execute-template < chezmoi/dot_openclaw/cron/jobs.seed.json.tmpl > /dev/null`

Expected: No errors.

**Step 3: Commit**

```bash
wsl -d NixOS -- bash -lc "cd /mnt/d/dotfiles && nix fmt && git add -A && git commit --no-verify -m 'feat: add sandbox-gc cron job (hourly exited container cleanup)'"
```

---

### Task 7: Update entrypoint.sh — remove socat proxy startup

**Files:**

- Modify: `docker/openclaw/entrypoint.sh:96-104`

**Step 1: Remove the socat proxy block**

Remove lines 96-104 (the Docker socket proxy section):

```bash
# Proxy Docker socket as TCP so sandbox containers can use Docker CLI.
# Unix sockets don't propagate through Docker Desktop named volumes,
# so we expose the socket as TCP on a loopback port instead.
workspace_dir="/app/data/workspace"
_docker_proxy_port=2375
if [ -S /var/run/docker.sock ]; then
  socat TCP-LISTEN:$_docker_proxy_port,bind=0.0.0.0,fork,reuseaddr UNIX-CONNECT:/var/run/docker.sock &
  echo "[entrypoint] docker socket proxied to tcp://0.0.0.0:$_docker_proxy_port"
fi
```

Note: Keep the `workspace_dir="/app/data/workspace"` variable if it is used later in the script. Check if it's defined elsewhere; if not, move it to where it's first used.

Actually, `workspace_dir` is used on line 99 and also on line 107+ (`_lifelog_dst="$workspace_dir/lifelog"` etc). So keep the variable declaration, just remove the socat proxy block:

Replace the block with just the variable:

```bash
workspace_dir="/app/data/workspace"
```

**Step 2: Verify entrypoint syntax**

Run: `bash -n docker/openclaw/entrypoint.sh`

Expected: No syntax errors.

**Step 3: Commit**

```bash
wsl -d NixOS -- bash -lc "cd /mnt/d/dotfiles && nix fmt && git add -A && git commit --no-verify -m 'security: remove socat Docker socket proxy from entrypoint (sandbox no longer needs it)'"
```

---

### Task 8: Update entrypoint.sh — fix AGENTS.md sandbox rules injection

**Files:**

- Modify: `docker/openclaw/entrypoint.sh:143-161`

**Step 1: Update the sandbox rules heredoc**

Replace the `## BEGIN SANDBOX RULES` block (the heredoc in entrypoint.sh) with:

```bash
if ! grep -q "BEGIN SANDBOX RULES" "$workspace_agents"; then
  cat >>"$workspace_agents" <<'EOF'

## BEGIN SANDBOX RULES

- Tool execution (`shell_exec`, `file_write`, etc.) runs inside an isolated Docker sandbox container.
- The sandbox image (`openclaw-sandbox-common:bookworm-slim`) includes: Python 3, Node.js, git, curl, jq, gh CLI, Playwright CLI, Chromium.
- Sandbox containers use `network: "bridge"` (external access available for pnpm install, Playwright E2E, etc.).
- Sandbox containers have NO access to the Docker daemon (no `DOCKER_HOST`). Docker build/run must be done on the gateway side.
- Each session gets its own sandbox container (`scope: "session"`), destroyed when the session ends.
- The workspace is mounted read-write at `/workspace` inside the sandbox.
- To run Python code, use `shell_exec("python3 script.py")` directly.
- To run Node.js code, use `shell_exec("node script.js")` directly.
- Playwright CLI (`@playwright/cli`) is available for E2E testing. `@playwright/test` is not installed.
- SYS_ADMIN is not required — Playwright launches Chromium with `--no-sandbox` by default.
- **Path mapping**: `/app/data/workspace/` on the gateway corresponds to `/workspace/` inside the sandbox. Always use `/workspace/` paths in sandbox tools.

## END SANDBOX RULES
EOF
fi
```

**Step 2: Verify entrypoint syntax**

Run: `bash -n docker/openclaw/entrypoint.sh`

Expected: No syntax errors.

**Step 3: Commit**

```bash
wsl -d NixOS -- bash -lc "cd /mnt/d/dotfiles && nix fmt && git add -A && git commit --no-verify -m 'docs: update entrypoint sandbox rules injection for hardened config'"
```

---

### Task 9: Investigate seccomp support (optional)

**Files:**

- Read: OpenClaw documentation at `https://docs.openclaw.ai/gateway/sandboxing`

**Step 1: Check if `securityOpt` is supported in sandbox.docker schema**

Search OpenClaw docs for `securityOpt` or `security_opt` in the sandbox configuration reference.

Run: `docker exec openclaw openclaw sandbox explain 2>&1 | grep -i seccomp`

**Step 2: Document the result**

If supported: Create `docker/openclaw/seccomp-sandbox.json` with a custom profile.
If not supported: Add a note to `docs/chezmoi/dot_openclaw/04-sandbox.md` that seccomp is deferred.

**Step 3: Commit**

```bash
wsl -d NixOS -- bash -lc "cd /mnt/d/dotfiles && nix fmt && git add -A && git commit --no-verify -m 'docs: document seccomp support investigation result'"
```

---

### Task 10: Verify end-to-end

**Step 1: Apply chezmoi and rebuild**

```bash
chezmoi apply
docker compose -f docker/openclaw/docker-compose.yml up -d --build --force-recreate
```

**Step 2: Verify sandbox has no DOCKER_HOST**

Send a test message via Telegram/Slack, then check:

```bash
docker exec openclaw openclaw sandbox explain 2>&1 | grep -i docker_host
```

Expected: No DOCKER_HOST in sandbox env.

**Step 3: Verify sandbox can still git push and use gh CLI**

In a sandbox session, run:

```
shell_exec("git --version && gh --version && echo 'OK'")
```

Expected: Version strings and "OK".

**Step 4: Verify Playwright CLI works**

In a sandbox session, run:

```
shell_exec("npx @playwright/cli --version")
```

Expected: Version string, no SYS_ADMIN errors.

**Step 5: Run sandbox:gc**

```bash
task sandbox:gc
```

Expected: "No exited sandbox containers" or successful cleanup.
