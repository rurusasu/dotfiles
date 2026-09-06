# Containerized ComfyUI MCP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a persistent, loopback-only ComfyUI MCP Docker service that connects to the native Metal-backed ComfyUI server, registers with Codex, and proves that a workflow submitted from ComfyUI Web is visible through the same MCP queue.

**Architecture:** Native ComfyUI remains on macOS at `127.0.0.1:8288`; Docker Desktop host networking lets a hardened Node.js container reach that loopback service without exposing ComfyUI to the LAN. The container serves native Streamable HTTP MCP at `127.0.0.1:9100/mcp`, while Codex consumes the URL generated from the repository's unified MCP data.

**Tech Stack:** Node.js 26.7.0 Current, `comfyui-mcp` 0.52.118, `@modelcontextprotocol/sdk` 1.30.0, Docker Desktop host networking, Docker Compose, Go Task, Python `unittest`, Pester, chezmoi, Codex MCP, ComfyUI REST/WebSocket API, Safari computer-use acceptance.

**Spec:** `docs/superpowers/specs/2026-08-26-comfyui-mcp-container-design.md`

## Global Constraints

- Use `node:26.7.0-bookworm-slim@sha256:4db36457f406501e6f608802e5da617e5fbd0e80b75901b6a09de1ae5a667d32` exactly.
- Pin `comfyui-mcp` to `0.52.118` and `@modelcontextprotocol/sdk` to `1.30.0`; commit `package-lock.json` and use `npm ci --omit=dev`.
- Keep native ComfyUI at `http://127.0.0.1:8288`; do not change its launch service, model store, custom nodes, workflow graph, or Metal execution path.
- Expose MCP only at `http://127.0.0.1:9100/mcp`; do not publish ComfyUI or MCP on `0.0.0.0`, a LAN address, a tunnel, or a cloud endpoint.
- Name the service `comfyui-mcp`; do not label ComfyUI or the MCP service as dedicated to MiniMax H3.
- Run the container non-root with a read-only root filesystem, `no-new-privileges`, no Docker socket, no credentials, and no host ComfyUI/model/workflow mounts.
- Use the direct MCP tool surface, not compact meta-tool mode.
- Do not install ComfyUI Agent Panel or distribute this MCP registration to Hermes, Claude Desktop, Cursor, Gemini, or VS Code.
- Preserve the user's unrelated dirty changes in `flake.lock`, `nix/packages/sets.nix`, `tests/bash/macos_config.bats`, and `tests/bash/package_catalog.bats`; stage only files owned by each task.
- Treat a running container or open TCP port as insufficient. Acceptance requires MCP initialization, `tools/list`, `get_system_stats`, queue agreement, and Web UI execution start.

---

### Task 1: Build the pinned MCP image and protocol probes

**Files:**

- Create: `tests/python/test_comfyui_mcp_image_contract.py`
- Create: `docker/comfyui-mcp/package.json`
- Create: `docker/comfyui-mcp/package-lock.json`
- Create: `docker/comfyui-mcp/Dockerfile`
- Create: `docker/comfyui-mcp/healthcheck.mjs`
- Create: `docker/comfyui-mcp/smoke.mjs`

**Interfaces:**

- Consumes: Node image tag/digest and package versions from the approved spec.
- Produces: image `local/comfyui-mcp:0.52.118-node26.7.0`; exported function `probeMcp({ checkQueue?: boolean }): Promise<ProbeResult>`; executable `/app/healthcheck.mjs` and `/app/smoke.mjs`.

- [ ] **Step 1: Write the failing image contract test**

Create `tests/python/test_comfyui_mcp_image_contract.py` with these exact path constants and assertions:

```python
"""Build and runtime contract for the containerized ComfyUI MCP service."""

from __future__ import annotations

import json
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
MCP_ROOT = REPOSITORY_ROOT / "docker" / "comfyui-mcp"
DOCKERFILE = MCP_ROOT / "Dockerfile"
PACKAGE_JSON = MCP_ROOT / "package.json"
PACKAGE_LOCK = MCP_ROOT / "package-lock.json"
HEALTHCHECK = MCP_ROOT / "healthcheck.mjs"
SMOKE = MCP_ROOT / "smoke.mjs"


class ComfyUiMcpImageContractTests(unittest.TestCase):
    def test_node_and_mcp_versions_are_exactly_pinned(self) -> None:
        dockerfile = DOCKERFILE.read_text(encoding="utf-8")
        package = json.loads(PACKAGE_JSON.read_text(encoding="utf-8"))

        self.assertIn(
            "node:26.7.0-bookworm-slim@sha256:"
            "4db36457f406501e6f608802e5da617e5fbd0e80b75901b6a09de1ae5a667d32",
            dockerfile,
        )
        self.assertIn('test "$(node --version)" = "v26.7.0"', dockerfile)
        self.assertEqual(package["engines"], {"node": "26.7.0"})
        self.assertEqual(package["dependencies"]["comfyui-mcp"], "0.52.118")
        self.assertEqual(
            package["dependencies"]["@modelcontextprotocol/sdk"], "1.30.0"
        )
        self.assertTrue(PACKAGE_LOCK.is_file())

    def test_image_installs_locked_production_dependencies_and_runs_non_root(self) -> None:
        dockerfile = DOCKERFILE.read_text(encoding="utf-8")

        self.assertIn("npm ci --omit=dev", dockerfile)
        self.assertIn("USER node", dockerfile)
        self.assertIn('ENTRYPOINT ["node_modules/.bin/comfyui-mcp"]', dockerfile)
        self.assertIn('HEALTHCHECK', dockerfile)
        self.assertIn('CMD ["node", "/app/healthcheck.mjs"]', dockerfile)

    def test_healthcheck_performs_mcp_handshake_discovery_and_read_only_call(self) -> None:
        healthcheck = HEALTHCHECK.read_text(encoding="utf-8")

        self.assertIn("StreamableHTTPClientTransport", healthcheck)
        self.assertIn("await client.connect(transport)", healthcheck)
        self.assertIn("await client.listTools()", healthcheck)
        self.assertIn('name: "get_system_stats"', healthcheck)
        self.assertIn('arguments: { action: "stats" }', healthcheck)
        self.assertIn("await client.close()", healthcheck)
        self.assertNotIn('name: "enqueue_workflow"', healthcheck)

    def test_smoke_probe_reads_queue_without_mutating_it(self) -> None:
        smoke = SMOKE.read_text(encoding="utf-8")

        self.assertIn("probeMcp({ checkQueue: true })", smoke)
        self.assertNotIn("enqueue_workflow", smoke)
        self.assertNotIn("cancel", smoke)
        self.assertNotIn("clear", smoke)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the focused test and verify the RED state**

Run:

```bash
python3 -m unittest tests/python/test_comfyui_mcp_image_contract.py -v
```

Expected: all four tests error with `FileNotFoundError` because `docker/comfyui-mcp/` does not exist yet.

- [ ] **Step 3: Create the pinned package manifest and lock file**

Create `docker/comfyui-mcp/package.json`:

```json
{
  "name": "dotfiles-comfyui-mcp",
  "version": "1.0.0",
  "private": true,
  "description": "Containerized Streamable HTTP MCP bridge for native ComfyUI",
  "license": "UNLICENSED",
  "type": "module",
  "engines": {
    "node": "26.7.0"
  },
  "dependencies": {
    "@modelcontextprotocol/sdk": "1.30.0",
    "comfyui-mcp": "0.52.118"
  }
}
```

Generate the deterministic lock file without executing lifecycle scripts on the host:

```bash
cd docker/comfyui-mcp
npm install --package-lock-only --ignore-scripts
cd ../..
```

Confirm the resolved top-level versions:

```bash
npm --prefix docker/comfyui-mcp pkg get engines dependencies
```

Expected: Node `26.7.0`, MCP SDK `1.30.0`, and ComfyUI MCP `0.52.118`.

- [ ] **Step 4: Implement the reusable MCP health probe**

Create `docker/comfyui-mcp/healthcheck.mjs`:

```javascript
import { pathToFileURL } from "node:url";

import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";

const ENDPOINT = new URL(process.env.COMFYUI_MCP_URL ?? "http://127.0.0.1:9100/mcp");
const REQUIRED_TOOLS = Object.freeze([
  "get_system_stats",
  "queue",
  "get_workflow",
  "create_workflow",
  "enqueue_workflow",
]);

export async function probeMcp({ checkQueue = false } = {}) {
  const client = new Client({
    name: "dotfiles-comfyui-mcp-probe",
    version: "1.0.0",
  });
  const transport = new StreamableHTTPClientTransport(ENDPOINT);

  try {
    await client.connect(transport);
    const catalog = await client.listTools();
    const names = catalog.tools.map((tool) => tool.name).sort();
    const missing = REQUIRED_TOOLS.filter((name) => !names.includes(name));
    if (missing.length > 0) {
      throw new Error(`missing required MCP tools: ${missing.join(", ")}`);
    }

    const stats = await client.callTool({
      name: "get_system_stats",
      arguments: { action: "stats" },
    });
    if (stats.isError) {
      throw new Error(`get_system_stats failed: ${JSON.stringify(stats)}`);
    }
    const statsText = JSON.stringify(stats).toLowerCase();
    if (!statsText.includes("mps")) {
      throw new Error("get_system_stats did not report the native MPS device");
    }

    const queue = checkQueue
      ? await client.callTool({ name: "queue", arguments: { action: "list" } })
      : undefined;
    if (queue?.isError) {
      throw new Error(`queue list failed: ${JSON.stringify(queue)}`);
    }

    return { endpoint: ENDPOINT.href, names, stats, queue };
  } finally {
    await client.close().catch(() => undefined);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await probeMcp();
}
```

- [ ] **Step 5: Implement the evidence-producing smoke command**

Create `docker/comfyui-mcp/smoke.mjs`:

```javascript
import { probeMcp } from "./healthcheck.mjs";

const result = await probeMcp({ checkQueue: true });
console.log(
  JSON.stringify(
    {
      ok: true,
      endpoint: result.endpoint,
      toolCount: result.names.length,
      requiredTools: [
        "get_system_stats",
        "queue",
        "get_workflow",
        "create_workflow",
        "enqueue_workflow",
      ].filter((name) => result.names.includes(name)),
      stats: result.stats,
      queue: result.queue,
    },
    null,
    2
  )
);
```

- [ ] **Step 6: Implement the multi-stage, non-root Docker image**

Create `docker/comfyui-mcp/Dockerfile`:

```dockerfile
FROM node:26.7.0-bookworm-slim@sha256:4db36457f406501e6f608802e5da617e5fbd0e80b75901b6a09de1ae5a667d32 AS dependencies

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates g++ make python3 \
    && rm -rf /var/lib/apt/lists/*

COPY package.json package-lock.json ./

RUN test "$(node --version)" = "v26.7.0" \
    && npm ci --omit=dev

FROM node:26.7.0-bookworm-slim@sha256:4db36457f406501e6f608802e5da617e5fbd0e80b75901b6a09de1ae5a667d32 AS runtime

WORKDIR /app

COPY --from=dependencies --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node package.json package-lock.json healthcheck.mjs smoke.mjs ./

ENV COMFYUI_MCP_DATA_DIR=/data \
    COMFYUI_MCP_FORCE_REMOTE=1 \
    COMFYUI_URL=http://127.0.0.1:8288 \
    HOME=/data \
    MCP_HOST=127.0.0.1 \
    MCP_PORT=9100 \
    MCP_TRANSPORT=http \
    NODE_ENV=production \
    NPM_CONFIG_UPDATE_NOTIFIER=false

RUN test "$(node --version)" = "v26.7.0"

USER node

HEALTHCHECK --interval=30s --timeout=15s --start-period=30s --retries=3 \
  CMD ["node", "/app/healthcheck.mjs"]

ENTRYPOINT ["node_modules/.bin/comfyui-mcp"]
CMD ["--http", "--host", "127.0.0.1", "--port", "9100", "--comfyui-url", "http://127.0.0.1:8288", "--force-remote"]
```

- [ ] **Step 7: Run the focused test and verify GREEN**

Run:

```bash
python3 -m unittest tests/python/test_comfyui_mcp_image_contract.py -v
```

Expected: `Ran 4 tests` and `OK`.

- [ ] **Step 8: Build and inspect the image**

Run:

```bash
docker buildx imagetools inspect node:26.7.0-bookworm-slim --format '{{json .Manifest}}' \
  | jq -e '.manifests[] | select(.platform.os == "linux" and .platform.architecture == "arm64")'
docker build --pull -t local/comfyui-mcp:0.52.118-node26.7.0 docker/comfyui-mcp
docker run --rm --entrypoint node local/comfyui-mcp:0.52.118-node26.7.0 --version
docker image inspect local/comfyui-mcp:0.52.118-node26.7.0 --format '{{json .Config.User}}'
```

Expected: the manifest query finds a Linux ARM64 entry, build succeeds, the version command prints `v26.7.0`, and image user is `node`.

- [ ] **Step 9: Commit Task 1 without staging unrelated work**

Run:

```bash
git add docker/comfyui-mcp tests/python/test_comfyui_mcp_image_contract.py
git diff --cached --name-status
task commit -- "feat: add containerized ComfyUI MCP image"
```

Expected staged paths: only `docker/comfyui-mcp/*` and `tests/python/test_comfyui_mcp_image_contract.py`.

---

### Task 2: Add the hardened Compose service and Taskfile lifecycle

**Files:**

- Create: `docker/comfyui-mcp/compose.yml`
- Create: `taskfiles/comfyui/taskfile.yml`
- Modify: `Taskfile.yml:4-42`
- Modify: `tests/python/test_comfyui_mcp_image_contract.py`

**Interfaces:**

- Consumes: image and probe scripts from Task 1.
- Produces: Compose service `comfyui-mcp`; public tasks `comfyui:mcp:config`, `build`, `up`, `down`, `ps`, `logs`, and `test`.

- [ ] **Step 1: Extend the contract test for Compose and Taskfile behavior**

Add these imports and constants to `tests/python/test_comfyui_mcp_image_contract.py`:

```python
import subprocess

COMPOSE_FILE = MCP_ROOT / "compose.yml"
ROOT_TASKFILE = REPOSITORY_ROOT / "Taskfile.yml"
COMFYUI_TASKFILE = REPOSITORY_ROOT / "taskfiles" / "comfyui" / "taskfile.yml"
```

Add this helper above the test class:

```python
def compose_config() -> dict[str, object]:
    result = subprocess.run(
        [
            "docker",
            "compose",
            "-f",
            str(COMPOSE_FILE),
            "config",
            "--format",
            "json",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)
```

Add these methods to `ComfyUiMcpImageContractTests`:

```python
    def test_compose_uses_host_network_without_published_ports(self) -> None:
        service = compose_config()["services"]["comfyui-mcp"]

        self.assertEqual(service["network_mode"], "host")
        self.assertNotIn("ports", service)
        self.assertTrue(service["read_only"])
        self.assertIn("no-new-privileges:true", service["security_opt"])
        self.assertRegex(service["user"], r"^\d+:\d+$")

    def test_compose_keeps_endpoints_loopback_only_and_mounts_no_host_runtime(self) -> None:
        service = compose_config()["services"]["comfyui-mcp"]
        serialized = json.dumps(service, sort_keys=True)

        self.assertIn("http://127.0.0.1:8288", serialized)
        self.assertIn("127.0.0.1", serialized)
        self.assertIn("9100", serialized)
        self.assertNotIn("0.0.0.0", serialized)
        self.assertNotIn("docker.sock", serialized)
        self.assertNotIn("models", serialized)
        self.assertNotIn("custom_nodes", serialized)
        self.assertNotIn("MiniMax", serialized)
        self.assertNotIn("H3", serialized)

    def test_compose_healthcheck_executes_the_real_mcp_probe(self) -> None:
        service = compose_config()["services"]["comfyui-mcp"]

        self.assertEqual(service["healthcheck"]["test"], [
            "CMD",
            "node",
            "/app/healthcheck.mjs",
        ])

    def test_taskfile_exposes_scoped_comfyui_mcp_lifecycle(self) -> None:
        root = ROOT_TASKFILE.read_text(encoding="utf-8")
        tasks = COMFYUI_TASKFILE.read_text(encoding="utf-8")

        self.assertIn("./taskfiles/comfyui/taskfile.yml", root)
        for name in ("config", "build", "up", "down", "ps", "logs", "test"):
            self.assertIn(f"comfyui:mcp:{name}:", tasks)
        self.assertIn("docker/comfyui-mcp/compose.yml", root)
        self.assertNotIn("docker compose down -v", tasks)
```

- [ ] **Step 2: Run the test and verify the new RED state**

Run:

```bash
python3 -m unittest tests/python/test_comfyui_mcp_image_contract.py -v
```

Expected: the original four tests pass; the four new tests fail because `compose.yml`, the Taskfile include, and lifecycle tasks are absent.

- [ ] **Step 3: Create the hardened Compose definition**

Create `docker/comfyui-mcp/compose.yml`:

```yaml
name: comfyui-mcp

services:
  comfyui-mcp:
    build:
      context: .
      dockerfile: Dockerfile
    image: local/comfyui-mcp:0.52.118-node26.7.0
    container_name: comfyui-mcp
    restart: unless-stopped
    network_mode: host
    # Compose runs as the host account's numeric identity so a host-created
    # bind mount remains writable when macOS UID 501 differs from image UID 1000.
    user: "${COMFYUI_MCP_UID:-1000}:${COMFYUI_MCP_GID:-1000}"
    read_only: true
    security_opt:
      - no-new-privileges:true
    tmpfs:
      - /tmp:rw,noexec,nosuid,nodev,size=64m
    environment:
      COMFYUI_MCP_DATA_DIR: /data
      COMFYUI_MCP_FORCE_REMOTE: "1"
      COMFYUI_URL: http://127.0.0.1:8288
      HOME: /data
      MCP_HOST: 127.0.0.1
      MCP_PORT: "9100"
      MCP_TRANSPORT: http
      NODE_ENV: production
    volumes:
      - type: bind
        source: ${COMFYUI_MCP_DATA_DIR:-${HOME}/.local/share/comfyui-mcp}
        target: /data
    command:
      - --http
      - --host
      - 127.0.0.1
      - --port
      - "9100"
      - --comfyui-url
      - http://127.0.0.1:8288
      - --force-remote
    healthcheck:
      test: ["CMD", "node", "/app/healthcheck.mjs"]
      interval: 30s
      timeout: 15s
      retries: 3
      start_period: 30s
```

- [ ] **Step 4: Add the dedicated Taskfile lifecycle**

Create `taskfiles/comfyui/taskfile.yml`:

```yaml
version: "3"

tasks:
  comfyui:mcp:config:
    desc: Validate the ComfyUI MCP Compose configuration
    preconditions:
      - sh: docker info
        msg: "Docker daemon is not running. Start Docker Desktop and try again."
    cmds:
      - docker compose -f {{.COMFYUI_MCP_COMPOSE_FILE}} config --quiet

  comfyui:mcp:build:
    desc: Build the pinned ComfyUI MCP image
    preconditions:
      - sh: docker info
        msg: "Docker daemon is not running. Start Docker Desktop and try again."
    cmds:
      - docker compose -f {{.COMFYUI_MCP_COMPOSE_FILE}} build --pull

  comfyui:mcp:up:
    desc: Start the local ComfyUI MCP service
    preconditions:
      - sh: docker info
        msg: "Docker daemon is not running. Start Docker Desktop and try again."
      - sh: test "$(uname -s)" = Darwin
        msg: "This initial ComfyUI MCP service supports Docker Desktop for macOS only."
    cmds:
      - mkdir -p "${COMFYUI_MCP_DATA_DIR:-$HOME/.local/share/comfyui-mcp}"
      - export COMFYUI_MCP_UID="$(id -u)" COMFYUI_MCP_GID="$(id -g)" && docker compose -f {{.COMFYUI_MCP_COMPOSE_FILE}} up -d --build

The `up` task passes the macOS account's UID/GID to Compose, so the bind-mounted
data directory created above is writable by the non-root container process even
when the image's `node` UID is different from the host UID.

  comfyui:mcp:down:
    desc: Stop the ComfyUI MCP service without deleting its data
    preconditions:
      - sh: docker info
        msg: "Docker daemon is not running. Start Docker Desktop and try again."
    cmds:
      - docker compose -f {{.COMFYUI_MCP_COMPOSE_FILE}} down

  comfyui:mcp:ps:
    desc: Show ComfyUI MCP service status
    preconditions:
      - sh: docker info
        msg: "Docker daemon is not running. Start Docker Desktop and try again."
    cmds:
      - docker compose -f {{.COMFYUI_MCP_COMPOSE_FILE}} ps

  comfyui:mcp:logs:
    desc: Follow ComfyUI MCP logs
    interactive: true
    preconditions:
      - sh: docker info
        msg: "Docker daemon is not running. Start Docker Desktop and try again."
    cmds:
      - docker compose -f {{.COMFYUI_MCP_COMPOSE_FILE}} logs -f --tail=100 comfyui-mcp

  comfyui:mcp:test:
    desc: Run a live MCP handshake, tool discovery, MPS, and queue probe
    preconditions:
      - sh: docker info
        msg: "Docker daemon is not running. Start Docker Desktop and try again."
    cmds:
      - docker compose -f {{.COMFYUI_MCP_COMPOSE_FILE}} exec -T comfyui-mcp node /app/smoke.mjs
```

- [ ] **Step 5: Register the Taskfile include and shared Compose path**

Add this variable below `HERMES_COMPOSE_FILE` in `Taskfile.yml`:

```yaml
vars:
  DISTRO: NixOS
  DOTFILES_PATH: ~/.dotfiles
  HERMES_COMPOSE_FILE: docker/hermes-service/compose.yml
  COMFYUI_MCP_COMPOSE_FILE: docker/comfyui-mcp/compose.yml
```

Add this flattened include below the existing `hermes` include:

```yaml
includes:
  hermes:
    taskfile: ./taskfiles/hermes/taskfile.yml
    flatten: true
  comfyui:
    taskfile: ./taskfiles/comfyui/taskfile.yml
    flatten: true
  hooks:
    taskfile: ./taskfiles/hooks/taskfile.yml
    flatten: true
```

- [ ] **Step 6: Validate the Compose model and verify GREEN**

Run:

```bash
docker compose -f docker/comfyui-mcp/compose.yml config --quiet
python3 -m unittest tests/python/test_comfyui_mcp_image_contract.py -v
task comfyui:mcp:config
```

Expected: Compose validation exits zero; all eight Python tests pass; the Taskfile config task exits zero.

- [ ] **Step 7: Commit Task 2 without staging unrelated work**

Run:

```bash
git add Taskfile.yml taskfiles/comfyui/taskfile.yml docker/comfyui-mcp/compose.yml tests/python/test_comfyui_mcp_image_contract.py
git diff --cached --name-status
task commit -- "feat: manage ComfyUI MCP lifecycle"
```

Expected staged paths: exactly the four paths listed above.

---

### Task 3: Register the Streamable HTTP MCP endpoint with Codex

**Files:**

- Modify: `chezmoi/.chezmoidata/mcp_servers.yaml:245-269`
- Modify: `scripts/powershell/tests/chezmoi/ChezmoiTemplate.Tests.ps1:598-616`
- Modify: `tests/python/test_comfyui_mcp_image_contract.py`

**Interfaces:**

- Consumes: loopback endpoint `http://127.0.0.1:9100/mcp` from Task 2 and the existing URL branch in `chezmoi/dot_codex/config.toml.tmpl`.
- Produces: generated `[mcp_servers.comfyui]` Codex configuration with URL-only Streamable HTTP settings.

- [ ] **Step 1: Add failing source-data contract tests**

Add this constant to `tests/python/test_comfyui_mcp_image_contract.py`:

```python
MCP_SERVERS = REPOSITORY_ROOT / "chezmoi" / ".chezmoidata" / "mcp_servers.yaml"
```

Add this test method:

```python
    def test_unified_mcp_data_declares_codex_only_comfyui_url(self) -> None:
        content = MCP_SERVERS.read_text(encoding="utf-8")
        marker = "  - name: comfyui\n"
        start = content.index(marker)
        next_entry = content.find("\n  - name:", start + len(marker))
        entry = content[start:] if next_entry == -1 else content[start:next_entry]

        self.assertIn('url: "http://127.0.0.1:9100/mcp"', entry)
        self.assertIn("      - codex", entry)
        for unsupported in (
            "claude-code",
            "claude-desktop",
            "cursor",
            "gemini",
            "vscode",
            "hermes",
        ):
            self.assertNotIn(unsupported, entry)
        self.assertNotIn("command:", entry)
        self.assertNotIn("args:", entry)
```

Add this Pester case inside `Context 'Codex remote MCP テンプレート'`:

```powershell
        It 'should declare the local ComfyUI MCP as Codex-only Streamable HTTP' {
            $mcpServersPath = Join-Path $script:chezmoiRoot '.chezmoidata/mcp_servers.yaml'
            $content = Get-Content -LiteralPath $mcpServersPath -Raw
            $match = [regex]::Match(
                $content,
                '(?ms)^  - name: comfyui\s*$.*?(?=^  - name:|\z)'
            )

            $match.Success | Should -BeTrue -Because 'ComfyUI MCP must be declared once in unified data'
            $entry = $match.Value
            $entry | Should -Match 'url:\s*"http://127\.0\.0\.1:9100/mcp"'
            $entry | Should -Match '(?m)^\s+- codex\s*$'
            $entry | Should -Not -Match '(?m)^\s+command:'
            $entry | Should -Not -Match '(?m)^\s+args:'
            foreach ($unsupported in @('claude-code', 'claude-desktop', 'cursor', 'gemini', 'vscode', 'hermes')) {
                $entry | Should -Not -Match "(?m)^\s+- $unsupported\s*$"
            }
        }
```

- [ ] **Step 2: Run focused tests and verify the RED state**

Run:

```bash
python3 -m unittest tests/python/test_comfyui_mcp_image_contract.py -v
pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1 \
  -Path scripts/powershell/tests/chezmoi/ChezmoiTemplate.Tests.ps1 \
  -MinimumCoverage 0
```

Expected: the new Python and Pester cases fail because no `comfyui` MCP data entry exists.

- [ ] **Step 3: Add the Codex-only MCP source entry**

Insert this entry before the local-only VS Code services near the end of `chezmoi/.chezmoidata/mcp_servers.yaml`:

```yaml
# ComfyUI - Local Streamable HTTP sidecar for native Metal-backed ComfyUI
- name: comfyui
  url: "http://127.0.0.1:9100/mcp"
  supports:
    - codex
```

- [ ] **Step 4: Verify generated Codex TOML before applying it**

Render the managed target from the working-tree source and inspect only the new block:

```bash
chezmoi -S chezmoi execute-template < chezmoi/dot_codex/config.toml.tmpl > /tmp/codex-config-comfyui.toml
rg -n -A3 '^\[mcp_servers\.comfyui\]$' /tmp/codex-config-comfyui.toml
```

Expected block:

```toml
[mcp_servers.comfyui]
url = "http://127.0.0.1:9100/mcp"
```

The block must contain no `command`, `args`, or environment table.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run:

```bash
python3 -m unittest tests/python/test_comfyui_mcp_image_contract.py -v
pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1 \
  -Path scripts/powershell/tests/chezmoi/ChezmoiTemplate.Tests.ps1 \
  -MinimumCoverage 0
```

Expected: all Python tests pass and the targeted Pester suite reports zero failures.

- [ ] **Step 6: Commit Task 3 without staging unrelated work**

Run:

```bash
git add chezmoi/.chezmoidata/mcp_servers.yaml scripts/powershell/tests/chezmoi/ChezmoiTemplate.Tests.ps1 tests/python/test_comfyui_mcp_image_contract.py
git diff --cached --name-status
task commit -- "feat: register ComfyUI MCP for Codex"
```

Expected staged paths: exactly the three paths listed above.

---

### Task 4: Document setup, operation, and security boundaries

**Files:**

- Create: `docs/comfyui/mcp.md`
- Modify: `tests/python/test_comfyui_mcp_image_contract.py`

**Interfaces:**

- Consumes: Taskfile commands and endpoint contracts from Tasks 1-3.
- Produces: an operator runbook that distinguishes Docker health, MCP usability, Web execution start, and full render completion.

- [ ] **Step 1: Add a failing documentation contract**

Add this constant:

```python
RUNBOOK = REPOSITORY_ROOT / "docs" / "comfyui" / "mcp.md"
```

Add this test method:

```python
    def test_runbook_documents_required_operation_and_security_boundaries(self) -> None:
        runbook = RUNBOOK.read_text(encoding="utf-8")

        for command in (
            "task comfyui:mcp:build",
            "task comfyui:mcp:up",
            "task comfyui:mcp:test",
            "task comfyui:mcp:ps",
            "task comfyui:mcp:logs",
            "task comfyui:mcp:down",
        ):
            self.assertIn(command, runbook)
        self.assertIn("Enable host networking", runbook)
        self.assertIn("http://127.0.0.1:8288", runbook)
        self.assertIn("http://127.0.0.1:9100/mcp", runbook)
        self.assertIn("get_system_stats", runbook)
        self.assertIn("tools/list", runbook)
        self.assertIn("ComfyUI Web", runbook)
        self.assertIn("LAN", runbook)
        self.assertIn("Agent Panel", runbook)
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
python3 -m unittest tests/python/test_comfyui_mcp_image_contract.py -v
```

Expected: the documentation test errors with `FileNotFoundError` for `docs/comfyui/mcp.md`; all preceding tests remain green.

- [ ] **Step 3: Write the operator runbook**

Create `docs/comfyui/mcp.md` with these exact top-level sections and operational content:

````markdown
# ComfyUI MCP

## Architecture

ComfyUI runs natively on macOS at `http://127.0.0.1:8288` so generation uses Apple Metal. The Docker service runs only the MCP control plane and exposes Streamable HTTP at `http://127.0.0.1:9100/mcp`. ComfyUI Web remains the workflow editor and execution surface.

## One-time Docker Desktop setting

Open Docker Desktop, select **Settings > Resources > Network**, enable **Enable host networking**, then choose **Apply and restart**. Do not change ComfyUI to listen on `0.0.0.0`; both ComfyUI and MCP must remain unavailable from the LAN.

## Build and start

```text
task comfyui:mcp:build
task comfyui:mcp:up
task comfyui:mcp:ps
```

## Verify MCP

```text
task comfyui:mcp:test
```

Success requires an MCP initialization, `tools/list`, a read-only `get_system_stats` result containing the `mps` device, and a read-only queue listing. A running container or TCP port alone is not proof.

## Register Codex

Render and apply only the managed Codex target from this repository's chezmoi source, then verify it:

```text
chezmoi -S chezmoi apply --no-tty "$HOME/.codex/config.toml"
codex mcp list --json
```

A newly started Codex task discovers `comfyui` at `http://127.0.0.1:9100/mcp`. The task that changed the config may require restart before native MCP tools appear.

## Run from ComfyUI Web

Open `http://127.0.0.1:8288`, load the workflow, and press **Run**. The Web queue and the MCP `queue` tool must show the same running or pending job. Queue acceptance and the first executing node prove the integration; a full MiniMax video render may continue much longer.

## Logs and status

```text
task comfyui:mcp:ps
task comfyui:mcp:logs
```

If ComfyUI is stopped, the MCP container becomes unhealthy but does not start or reconfigure ComfyUI.

## Stop

```text
task comfyui:mcp:down
```

This stops the service without deleting its persistent data directory.

## Upgrade

Update the exact Node image version and digest, the exact `comfyui-mcp` package version, and `package-lock.json` in one reviewed change. Rebuild and repeat the repository, MCP, MPS, queue, and ComfyUI Web acceptance checks. Do not replace pins with `latest`.

## Security and scope

Docker host networking gives this trusted container access to host loopback services. The service runs non-root with a read-only root filesystem, no credentials, no Docker socket, and no host model or workflow mounts. Agent Panel, LAN exposure, model downloads, custom-node installation, and automatic ComfyUI process control are outside this setup.
````

- [ ] **Step 4: Run the focused test and verify GREEN**

Run:

```bash
python3 -m unittest tests/python/test_comfyui_mcp_image_contract.py -v
git diff --check -- docs/comfyui/mcp.md
```

Expected: all Python tests pass and `git diff --check` exits zero.

- [ ] **Step 5: Commit Task 4 without staging unrelated work**

Run:

```bash
git add docs/comfyui/mcp.md tests/python/test_comfyui_mcp_image_contract.py
git diff --cached --name-status
task commit -- "docs: add ComfyUI MCP runbook"
```

Expected staged paths: exactly the runbook and focused contract test.

---

### Task 5: Enable host networking and complete live MCP/Web acceptance

**Files:**

- Runtime change: Docker Desktop host networking setting
- Runtime change: `~/.codex/config.toml` generated from `chezmoi/dot_codex/config.toml.tmpl`
- Runtime service: Docker Compose project `comfyui-mcp`
- Runtime UI: Safari at `http://127.0.0.1:8288`

**Interfaces:**

- Consumes: all repository deliverables from Tasks 1-4 and the existing native ComfyUI launch service.
- Produces: live `comfyui-mcp` container, native Codex registration, MCP protocol evidence, and a Web-submitted workflow visible in the MCP queue.

- [ ] **Step 1: Record the pre-change runtime state**

Run:

```bash
docker ps --format '{{json .}}'
launchctl print "gui/$(id -u)/local.comfyui"
python3 -c "import json,urllib.request; print(json.load(urllib.request.urlopen('http://127.0.0.1:8288/system_stats', timeout=5))['devices'][0]['type'])"
lsof -nP -iTCP:9100 -sTCP:LISTEN
```

Expected: Docker is reachable; native ComfyUI is running; direct system stats report `mps`; port 9100 has no listener. If port 9100 is occupied, stop and report the owning process instead of replacing it.

- [ ] **Step 2: Enable Docker Desktop host networking through the UI**

Use the computer-use workflow to open Docker Desktop and navigate to **Settings > Resources > Network**. Enable **Enable host networking**, choose **Apply and restart**, and wait for `docker desktop status` to report a running engine.

After restart, run:

```bash
docker ps --format '{{json .}}'
```

Expected: previously running `restart: unless-stopped` services return. Report any existing service that does not recover; do not delete or recreate unrelated volumes.

- [ ] **Step 3: Prove host-loopback reachability before starting MCP**

Run the pinned image with its entrypoint replaced by a read-only Node probe:

```bash
docker run --rm --network host --entrypoint node \
  local/comfyui-mcp:0.52.118-node26.7.0 \
  -e "fetch('http://127.0.0.1:8288/system_stats').then(r=>r.json()).then(d=>{console.log(d.devices[0].type);if(d.devices[0].type!=='mps')process.exit(1)})"
```

Expected: `mps`. If this fails, stop; do not change ComfyUI to `0.0.0.0`.

- [ ] **Step 4: Start the MCP service and wait for real health**

Run:

```bash
task comfyui:mcp:up
task comfyui:mcp:ps
```

Poll `task comfyui:mcp:ps` for at most 90 seconds in intervals no longer than 10 seconds. Expected: container `comfyui-mcp` becomes `healthy`. If it becomes `unhealthy`, inspect `task comfyui:mcp:logs` and report the MCP/tool failure rather than treating process liveness as success.

- [ ] **Step 5: Run the standalone MCP acceptance client**

Run:

```bash
task comfyui:mcp:test
```

Expected JSON evidence:

```json
{
  "ok": true,
  "endpoint": "http://127.0.0.1:9100/mcp",
  "requiredTools": [
    "get_system_stats",
    "queue",
    "get_workflow",
    "create_workflow",
    "enqueue_workflow"
  ]
}
```

The `stats` content must contain `mps`, and the initial `queue` result must match `GET http://127.0.0.1:8288/queue`.

- [ ] **Step 6: Apply the Codex target and verify registration**

First perform a targeted dry run:

```bash
chezmoi -S chezmoi apply --dry-run --verbose "$HOME/.codex/config.toml"
```

Confirm the diff only adds `[mcp_servers.comfyui]` and its URL. Then apply and verify:

```bash
chezmoi -S chezmoi apply --no-tty "$HOME/.codex/config.toml"
codex mcp list --json | jq '.[] | select(.name == "comfyui")'
```

Expected: one enabled `comfyui` entry at `http://127.0.0.1:9100/mcp`. Do not restart the current task merely to claim native tool availability; the standalone acceptance in Step 5 is the current-task proof, and the next Codex task is the native discovery proof.

- [ ] **Step 7: Submit the existing workflow from ComfyUI Web**

Use computer-use against Safari's existing `http://127.0.0.1:8288` tab:

1. Refresh the page after confirming the queue is empty.
2. Open `MiniMax-H3-Apple-Silicon-Q4` from the workflow library.
3. Fit the workflow to view and confirm there are no red unresolved-node boxes.
4. Click **Run** once.
5. Refresh accessibility/UI state and confirm one active or pending job and the first executing node.

Do not click **Run** repeatedly if the UI is slow. Do not alter workflow widgets, loaders, prompts, or links during this acceptance.

- [ ] **Step 8: Prove Web and MCP observe the same job**

While the Web UI shows the job, run:

```bash
task comfyui:mcp:test
python3 -c "import json,urllib.request; print(json.dumps(json.load(urllib.request.urlopen('http://127.0.0.1:8288/queue', timeout=5)), indent=2))"
```

Expected: MCP `queue` and direct `/queue` each show one matching running or pending prompt, and Safari remains connected. Record the prompt ID from both paths. Leave the user-authorized render running unless the user asks to stop it or ComfyUI reports a concrete execution error.

- [ ] **Step 9: Run final repository verification**

Run:

```bash
python3 -m unittest tests/python/test_comfyui_mcp_image_contract.py -v
pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1 \
  -Path scripts/powershell/tests/chezmoi/ChezmoiTemplate.Tests.ps1 \
  -MinimumCoverage 0
docker compose -f docker/comfyui-mcp/compose.yml config --quiet
task comfyui:mcp:test
git diff --check
git status --short
```

Expected: focused Python and Pester tests pass, Compose validates, live MCP acceptance returns `ok: true`, no whitespace errors exist, and only the four pre-existing unrelated dirty files remain uncommitted.

- [ ] **Step 10: Review commits and hand off the running service**

Run:

```bash
git log --oneline --decorate -5
git show --stat --oneline HEAD~3..HEAD
```

Report:

- repository files added or modified;
- Node.js, MCP package, image, and endpoint versions;
- Docker, MCP handshake, tool discovery, MPS, queue, and Web UI evidence;
- whether the render is still running, completed, or failed with a specific node error;
- that the next Codex task will natively load the new MCP entry;
- the unchanged unrelated dirty files.
