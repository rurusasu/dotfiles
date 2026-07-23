# Hermes X MCP Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run X's official hosted MCP bridge as an isolated Compose service and make the same `xapi` MCP endpoint available to every managed Hermes distribution.

**Architecture:** Add a Node 22 `xapi-mcp` image with pinned `@xdevplatform/xurl@1.3.1` and `mcp-proxy@6.5.4`. The service mounts the existing `.xurl` cache, exposes only an internal Streamable HTTP endpoint, and receives OAuth client credentials through Compose environment interpolation. Hermes distributions declare `http://xapi-mcp:8080/mcp`, while bootstrap source validation guarantees the URL exists in the root and every managed profile.

**Tech Stack:** Docker Compose, Node.js 22, `@xdevplatform/xurl`, `mcp-proxy`, Python `unittest`/PyYAML contract tests, Bash Bats, go-task.

## Global Constraints

- Use the X hosted endpoint `https://api.x.com/mcp` through the official `xurl mcp` bridge.
- Do not publish the X MCP port to the host.
- Do not commit `CLIENT_ID`, `CLIENT_SECRET`, bearer tokens, or `.xurl` contents.
- Keep the existing `hermes-browser` network and `.hermes/.xurl` runtime path.
- Preserve the distribution-owned profile configuration model; validate, do not inject, `xapi` configuration during bootstrap.
- Run tests first in the failing state, then implement the minimum behavior required by each test.

---

### Task 1: Add failing Compose and Taskfile contract tests

**Files:**
- Modify: `docker/hermes-agent/bootstrap/tests/test_compose_contract.py`
- Create: `docker/hermes-agent/bootstrap/tests/test_taskfile_contract.py`

**Interfaces:**
- Consumes: current `docker/hermes-agent/compose.yml` and `Taskfile.yml`.
- Produces: executable contracts for the `xapi-mcp` service and its task entry points.

- [ ] **Step 1: Write the failing Compose service test**

Add a test that requires an `xapi-mcp` service with:

```python
self.assertEqual(xapi["container_name"], "hermes-xapi-mcp")
self.assertEqual(xapi["image"], "local/hermes-xapi-mcp:latest")
self.assertEqual(xapi["networks"], ["hermes-browser"])
self.assertEqual(xapi["volumes"], [XURL_BIND])
self.assertNotIn("ports", xapi)
self.assertEqual(xapi["environment"], {
    "X_API_CLIENT_ID": "${X_API_CLIENT_ID:-}",
    "X_API_CLIENT_SECRET": "${X_API_CLIENT_SECRET:-}",
})
self.assertEqual(xapi["healthcheck"]["test"], ["CMD-SHELL", EXPECTED_TCP_HEALTHCHECK])
self.assertIn("xapi-mcp", self.services["hermes"]["depends_on"])
```

Also assert the service command contains `mcp-proxy`, `--server`, `stream`,
`--host`, `0.0.0.0`, `--port`, `8080`, and `hermes-xapi-mcp`.

- [ ] **Step 2: Write the failing Taskfile contract test**

Parse `Taskfile.yml` with PyYAML and require these commands:

```python
assert_command_contains("hermes:pull", "xapi-mcp")
assert_command_contains("hermes:xapi:auth", "xurl auth oauth2 --headless")
assert_command_contains("hermes:xapi:restart", "up -d --force-recreate xapi-mcp")
assert_command_contains("hermes:xapi:logs", "logs -f --tail=100 xapi-mcp")
```

- [ ] **Step 3: Run the focused tests and verify the expected failure**

Run:

```bash
python -m unittest docker/hermes-agent/bootstrap/tests/test_compose_contract.py
python -m unittest docker/hermes-agent/bootstrap/tests/test_taskfile_contract.py
```

Expected: failures identify the missing `xapi-mcp` service and task entries;
there must be no YAML import or test syntax error.

- [ ] **Step 4: Commit the red tests**

```bash
git add docker/hermes-agent/bootstrap/tests/test_compose_contract.py docker/hermes-agent/bootstrap/tests/test_taskfile_contract.py
git commit -m "test: define Hermes X MCP compose contracts"
```

### Task 2: Build the isolated X MCP image

**Files:**
- Create: `docker/hermes-xapi-mcp/Dockerfile`
- Create: `docker/hermes-xapi-mcp/package.json`
- Create: `docker/hermes-xapi-mcp/package-lock.json`
- Create: `docker/hermes-xapi-mcp/entrypoint.sh`

**Interfaces:**
- Consumes: `CLIENT_ID`, `CLIENT_SECRET`, and `/root/.xurl` at runtime.
- Produces: a stdio `xurl mcp https://api.x.com/mcp` bridge wrapped as a
  Streamable HTTP server on port 8080.

- [ ] **Step 1: Add the pinned package manifest**

Create `package.json` with production dependencies:

```json
{
  "name": "hermes-xapi-mcp",
  "private": true,
  "dependencies": {
    "@xdevplatform/xurl": "1.3.1",
    "mcp-proxy": "6.5.4"
  }
}
```

Generate the lockfile with `npm install --package-lock-only --ignore-scripts`
from `docker/hermes-xapi-mcp` and verify both exact versions are present.

- [ ] **Step 2: Add the bridge entrypoint**

Create `entrypoint.sh` that maps optional Compose names to the names expected
by xurl and then replaces the shell with the bridge:

```sh
#!/bin/sh
set -eu

if [ -n "${X_API_CLIENT_ID:-}" ]; then
  export CLIENT_ID="$X_API_CLIENT_ID"
fi
if [ -n "${X_API_CLIENT_SECRET:-}" ]; then
  export CLIENT_SECRET="$X_API_CLIENT_SECRET"
fi

exec node_modules/.bin/xurl mcp https://api.x.com/mcp
```

The production command will invoke this script as the child command of
`mcp-proxy`; it must keep stdout reserved for JSON-RPC and send diagnostics to
stderr through xurl.

- [ ] **Step 3: Add the Dockerfile**

Use `node:22-bookworm-slim`, copy the package manifests, run
`npm ci --omit=dev --ignore-scripts`, copy the entrypoint, set it executable,
set `NODE_ENV=production`, expose 8080 for the internal service, and add a
TCP healthcheck against `127.0.0.1:8080`.

- [ ] **Step 4: Build the image and run the image contract checks**

Run:

```bash
docker build -t local/hermes-xapi-mcp:test docker/hermes-xapi-mcp
docker run --rm local/hermes-xapi-mcp:test node --version
```

Expected: the image builds without running an OAuth flow during build, and
Node reports major version 22.

- [ ] **Step 5: Commit the image**

```bash
git add docker/hermes-xapi-mcp
git commit -m "feat: add isolated X MCP bridge image"
```

### Task 3: Wire `xapi-mcp` into Compose and Taskfile

**Files:**
- Modify: `docker/hermes-agent/compose.yml`
- Modify: `Taskfile.yml`
- Modify: `scripts/sh/hermes-agent.sh`
- Modify: `scripts/powershell/hermes-bootstrap.ps1`

**Interfaces:**
- Consumes: `local/hermes-xapi-mcp:latest`, host `${HERMES_DATA_DIR}/.xurl`,
  `X_API_CLIENT_ID`, and `X_API_CLIENT_SECRET`.
- Produces: a healthy internal `xapi-mcp` service available at
  `http://xapi-mcp:8080/mcp`; all bootstrap and update paths build/start it.

- [ ] **Step 1: Add the Compose service**

Add `xapi-mcp` with the following contract:

```yaml
xapi-mcp:
  build:
    context: ../hermes-xapi-mcp
    dockerfile: Dockerfile
  image: local/hermes-xapi-mcp:latest
  container_name: hermes-xapi-mcp
  restart: unless-stopped
  command:
    - node_modules/.bin/mcp-proxy
    - --server
    - stream
    - --host
    - 0.0.0.0
    - --port
    - "8080"
    - --
    - /usr/local/bin/hermes-xapi-mcp
  environment:
    X_API_CLIENT_ID: "${X_API_CLIENT_ID:-}"
    X_API_CLIENT_SECRET: "${X_API_CLIENT_SECRET:-}"
  volumes:
    - type: bind
      source: ${HERMES_DATA_DIR:-${USERPROFILE:-${HOME}}/.hermes}/.xurl
      target: /root/.xurl
  healthcheck:
    test: ["CMD-SHELL", "node -e \"const net=require('node:net');const s=net.connect({host:'127.0.0.1',port:8080},()=>{s.end();process.exit(0)});s.on('error',()=>process.exit(1));setTimeout(()=>process.exit(1),3000);\""]
    interval: 10s
    timeout: 5s
    retries: 12
    start_period: 10s
  networks:
    - hermes-browser
```

Add `xapi-mcp` to the Hermes `depends_on` map with
`condition: service_healthy`. Keep the X service free of host ports.

- [ ] **Step 2: Update stack build and auth operations**

Update every cross-platform Hermes build path to include `xapi-mcp`, including
the Unix and PowerShell bootstrap adapters. Add these Taskfile tasks with the
same Docker precondition style as existing Hermes tasks:

```yaml
hermes:xapi:auth:
  desc: Authenticate the X MCP bridge with the headless OAuth flow
  interactive: true
  cmds:
    - docker compose -f {{.HERMES_COMPOSE_FILE}} run --rm --no-deps --entrypoint /bin/sh xapi-mcp -lc 'node_modules/.bin/xurl auth oauth2 --headless'

hermes:xapi:restart:
  desc: Recreate the Hermes X MCP container
  cmds:
    - docker compose -f {{.HERMES_COMPOSE_FILE}} up -d --force-recreate xapi-mcp

hermes:xapi:logs:
  desc: Follow Hermes X MCP logs
  interactive: true
  cmds:
    - docker compose -f {{.HERMES_COMPOSE_FILE}} logs -f --tail=100 xapi-mcp
```

Use the service's mounted `.xurl` directory for the headless flow and never
place client credentials in the command arguments.

- [ ] **Step 3: Run Compose and Taskfile tests to verify they pass**

Run:

```bash
python -m unittest docker/hermes-agent/bootstrap/tests/test_compose_contract.py
python -m unittest docker/hermes-agent/bootstrap/tests/test_taskfile_contract.py
docker compose -f docker/hermes-agent/compose.yml config --quiet
```

Expected: all focused tests pass and Compose exits successfully.

- [ ] **Step 4: Commit the runtime wiring**

```bash
git add docker/hermes-agent/compose.yml Taskfile.yml scripts/sh/hermes-agent.sh scripts/powershell/hermes-bootstrap.ps1
git commit -m "feat: run X MCP as a Hermes compose service"
```

### Task 4: Enforce and document the all-profile MCP contract

**Files:**
- Modify: `docker/hermes-agent/bootstrap/hermes_bootstrap/source_contracts.py`
- Modify: `docker/hermes-agent/bootstrap/tests/test_source_contracts.py`
- Create: `docs/hermes-agent/xapi-mcp.md`
- Modify: `docs/hermes-agent/bootstrap.md`
- Modify: `docs/hermes-agent/profile-home-layout.md`

**Interfaces:**
- Consumes: staged root/profile `config.yaml` files.
- Produces: a validation error when any managed distribution lacks the
  canonical `xapi` MCP entry.

- [ ] **Step 1: Write failing source-contract tests**

Extend the valid fixture with:

```yaml
xapi:
  url: http://xapi-mcp:8080/mcp
  connect_timeout: 300
```

Add cases for missing `xapi`, wrong URL, missing timeout, non-integer timeout,
and extra keys. Assert the error identifies the distribution and
`config.yaml` without echoing secret values.

- [ ] **Step 2: Run the source-contract tests and verify RED**

Run:

```bash
python -m unittest docker/hermes-agent/bootstrap/tests/test_source_contracts.py
```

Expected: the updated valid fixture fails because the validator does not yet
require `xapi`.

- [ ] **Step 3: Implement the canonical xapi validator**

Add:

```python
_XAPI_MCP = {
    "url": "http://xapi-mcp:8080/mcp",
    "connect_timeout": 300,
}
```

Validate `mcp_servers.xapi` with the same strict mapping checks as Chrome,
while preserving all unrelated MCP entries. Invoke the validator for every
staged root/profile source already covered by the existing function.

- [ ] **Step 4: Run the source-contract tests and verify GREEN**

Run the same unittest command and expect all tests to pass.

- [ ] **Step 5: Document first login, runtime access, and recovery**

Document that `task hermes:xapi:auth` is required once with
`X_API_CLIENT_ID` and `X_API_CLIENT_SECRET` set, that the cache is shared at
`~/.hermes/.xurl`, and that each profile uses the internal URL. Include the
verification commands:

```bash
docker compose -f docker/hermes-agent/compose.yml ps xapi-mcp hermes
docker exec hermes hermes -p rick mcp test xapi
docker exec hermes hermes -p hoffman mcp test xapi
docker exec hermes hermes -p risarisa mcp test xapi
docker exec hermes hermes -p nancy mcp test xapi
```

- [ ] **Step 6: Commit the profile contract and docs**

```bash
git add docker/hermes-agent/bootstrap/hermes_bootstrap/source_contracts.py docker/hermes-agent/bootstrap/tests/test_source_contracts.py docs/hermes-agent/xapi-mcp.md docs/hermes-agent/bootstrap.md docs/hermes-agent/profile-home-layout.md
git commit -m "feat: require X MCP in every Hermes profile"
```

### Task 5: Verify the complete change

**Files:**
- Modify: none

- [ ] **Step 1: Run focused Python and shell tests**

```bash
python -m unittest discover -s docker/hermes-agent/bootstrap/tests
bats tests/bash/hermes_agent.bats
```

Expected: all tests pass with no new warnings or failures.

- [ ] **Step 2: Validate formatting and Compose contracts**

```bash
git diff --check
docker compose -f docker/hermes-agent/compose.yml config --quiet
task hermes:bootstrap:config
```

Expected: all commands exit 0. If Docker is unavailable, report that runtime
validation is environment-blocked while retaining the completed static tests.

- [ ] **Step 3: Build the production images**

```bash
task hermes:pull
```

Expected: `hermes`, `chromium`, `browser-mcp`, and `xapi-mcp` build
successfully without exposing credentials.

- [ ] **Step 4: Review the final diff and status**

```bash
git diff HEAD~4..HEAD --stat
git status --short --branch
```

Confirm the branch is `feat/hermes-x-mcp`, no `.xurl` files are tracked, and
only the intended Compose, Taskfile, bootstrap contract, image, tests, and
documentation files changed.
