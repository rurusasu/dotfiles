# Containerized ComfyUI MCP Design

## Goal

Run a persistent ComfyUI MCP service in Docker on the target Apple Silicon Mac,
connect it to the existing native ComfyUI server, register it with Codex, and
keep the ComfyUI Web UI as the primary place where the user opens and executes
workflows.

The completed system must let the user open
`http://127.0.0.1:8288`, load the existing workflow, press **Run**, and see the
same queue through MCP. The MCP service supplements the Web UI with workflow
inspection, validation, system statistics, and queue observation; it does not
replace the Web UI or move ComfyUI inference into Docker.

## Scope

This change covers:

- a dedicated Docker image and Compose service named `comfyui-mcp`;
- the latest stable Node.js release available at design time, Node.js 26.7.0;
- `comfyui-mcp` 0.52.118 from npm, pinned with a lock file;
- local-only Streamable HTTP MCP at `http://127.0.0.1:9100/mcp`;
- Codex MCP registration through the repository's unified MCP server data;
- Taskfile entry points for build, start, stop, logs, status, and live testing;
- repository contract tests and live MCP/Web UI acceptance checks;
- operator documentation for setup, operation, upgrade, and troubleshooting.

The host ComfyUI installation, models, custom nodes, launch configuration, and
workflow library remain outside Docker. The service must not be named or
described as dedicated to MiniMax H3. The existing MiniMax H3 workflow is the
live acceptance workload, not the identity of the ComfyUI service.

Installing ComfyUI Agent Panel, exposing ComfyUI or MCP to the LAN, adding API
keys, downloading models, changing the current workflow graph, moving Metal
inference into Docker, and distributing the connection to Hermes or other MCP
clients are out of scope.

## Chosen Architecture

Native ComfyUI continues to run under the existing macOS launch service and
listens only on `127.0.0.1:8288`. This preserves Apple Metal access and keeps
the unauthenticated ComfyUI API off the LAN.

The `comfyui-mcp` container uses Docker Desktop host networking. Host networking
is required because a normal bridge-network container cannot reach a macOS
service that listens only on host loopback; the live probe against
`host.docker.internal:8288` timed out, and `--network host` could not reach the
host loopback while Docker Desktop's host-networking feature was disabled.
Implementation therefore enables **Settings > Resources > Network > Enable
host networking** and applies the required Docker Desktop restart.

After that setting is enabled, the service uses `network_mode: host` and points
`COMFYUI_URL` at `http://127.0.0.1:8288`. The MCP HTTP listener also binds to
`127.0.0.1`, on port 9100. Compose does not declare a published port because
port mappings are ignored in host-network mode.

The runtime flow is:

```text
Codex
  -> http://127.0.0.1:9100/mcp
     -> comfyui-mcp 0.52.118 in Docker
        -> http://127.0.0.1:8288 REST API
        -> ws://127.0.0.1:8288/ws
           -> native ComfyUI on Apple Metal

Safari
  -> http://127.0.0.1:8288
     -> the same native ComfyUI queue and workflow library
```

The MCP server runs in remote mode even though its target URL is loopback. This
prevents container-local filesystem auto-detection from treating the container
as the ComfyUI installation. Runtime tools use ComfyUI's REST and WebSocket
interfaces; host-only filesystem and process-management tools are not accepted
as proof of the connection.

## Container Image and Runtime Contract

The image uses the official multi-architecture
`node:26.7.0-bookworm-slim` image, pinned to the verified OCI index digest
`sha256:4db36457f406501e6f608802e5da617e5fbd0e80b75901b6a09de1ae5a667d32`.
This digest includes Linux ARM64 support for the target Mac. The Dockerfile
must prove `node --version` reports `v26.7.0` during the build.

The package manifest pins `comfyui-mcp` to `0.52.118`, and `package-lock.json`
is committed. Installation uses `npm ci --omit=dev`; neither a floating npm
version nor `npx ...@latest` is allowed at container startup. Updating Node.js
or the MCP package requires an explicit lock/digest update and the full live
acceptance procedure.

The runtime command is equivalent to:

```text
comfyui-mcp --http --host 127.0.0.1 --port 9100 \
  --comfyui-url http://127.0.0.1:8288 --force-remote
```

The service runs as the image's non-root `node` user, uses a read-only root
filesystem, mounts a dedicated persistent data directory at `/data`, and uses
a temporary filesystem for `/tmp`. It sets `no-new-privileges` and receives no
Docker socket, host ComfyUI directory, model directory, workflow directory,
credential directory, or API key mount.

The service uses `restart: unless-stopped`. It does not own the native ComfyUI
process and must not restart, stop, or reconfigure that process automatically.
If ComfyUI is unavailable, MCP remains observable but reports the dependency as
unreachable and fails its health check.

## MCP Registration and Client Lifecycle

The unified MCP data file gains one server named `comfyui` with the URL
`http://127.0.0.1:9100/mcp` and Codex support. The generated Codex configuration
uses native Streamable HTTP rather than a per-session `docker run` stdio
command. This keeps container ownership in Compose and prevents Codex restarts
from creating duplicate MCP containers.

The service uses the package's direct tool surface, not compact meta-tool mode.
Codex therefore discovers named tools such as `get_system_stats`, `queue`, and
`enqueue_workflow` through a normal `tools/list` response.

The implementation applies only the generated Codex configuration target after
repository tests pass. The current Codex task may not hot-load a newly added
MCP declaration, so live acceptance uses a standalone MCP protocol client in
addition to `codex mcp list`. A newly started Codex task must discover the
`comfyui` server natively without another configuration change.

Hermes, Claude Desktop, Cursor, Gemini, and other clients do not receive this
entry in this scope.

## Web UI Execution Contract

ComfyUI Web remains the execution surface. The implementation must leave the
existing Web UI URL and native launch service unchanged. Acceptance opens the
registered workflow in Safari, confirms there are no unresolved node types,
and presses **Run** in the Web UI.

The Web submission is successful only when all of the following are observed:

1. the Web UI changes from an empty queue to a running or pending job;
2. the MCP `queue` tool reports the same job through the same ComfyUI backend;
3. ComfyUI accepts the prompt without immediate workflow-validation or
   missing-node errors;
4. the Web UI remains connected while the first execution node starts.

The MiniMax H3 render can be long-running. Queue acceptance and execution start
are the setup acceptance gate. Full video completion and visual-quality review
are recorded when practical, but a long render is not allowed to hide a broken
MCP or Web UI integration. The user may stop the render from the existing Web
UI after the integration evidence is captured.

MCP is not used to mutate the live browser canvas in this scope. A future live
canvas requirement would add and separately approve ComfyUI Agent Panel and its
orchestrator boundary.

## Health and Live Verification

The Compose health check performs a real MCP initialization and `tools/list`
exchange, then calls the read-only `get_system_stats` tool. A TCP-only port
check is insufficient because it does not prove MCP framing, tool discovery,
or ComfyUI reachability. The check closes its MCP session cleanly and must not
queue or mutate a workflow.

Live acceptance proves each layer separately:

1. Docker reports the container running with the expected image and non-root
   user.
2. `node --version` inside the image is exactly `v26.7.0`.
3. The installed npm package version is exactly `0.52.118`.
4. MCP initialization succeeds at `http://127.0.0.1:9100/mcp`.
5. `tools/list` includes `get_system_stats`, `queue`, `get_workflow`,
   `create_workflow`, and `enqueue_workflow`.
6. `get_system_stats` returns the native ComfyUI server and its `mps` device.
7. The MCP `queue` result and ComfyUI `/queue` response agree before and after
   the Web UI submits the workflow.
8. Safari can still operate the workflow at `http://127.0.0.1:8288`.

Container health, TCP reachability, a successful direct REST request, and a
Web UI screenshot are supporting evidence, not substitutes for the MCP
handshake and tool call.

## Security Boundary

Both HTTP listeners remain on loopback. No unauthenticated ComfyUI or MCP port
is published to `0.0.0.0`, the LAN address, a tunnel, or a cloud endpoint.

Docker Desktop host networking gives the container layer-4 access to host
loopback services. This is broader than a bridge network, so the image is kept
minimal, dependencies are pinned, the service runs non-root, the root
filesystem is read-only, no credentials are mounted, and no Docker socket is
available. The user-approved host-network setting applies globally to Docker
Desktop, but only containers explicitly configured with host networking use
it.

The MCP service is trusted local software and has workflow-execution tools.
Codex must not call queue mutation, cancellation, model download, custom-node
installation, or process-control tools unless the user request authorizes that
action. Health checks use read-only tools only.

## Failure Handling

- If Docker Desktop host networking is unavailable or conflicts with Enhanced
  Container Isolation, setup stops and reports the exact Docker setting rather
  than exposing ComfyUI on the LAN.
- If port 9100 is already in use, setup fails before replacing or stopping the
  owning process.
- If ComfyUI is down, the MCP container remains diagnosable and unhealthy; it
  does not launch a second ComfyUI instance.
- If MCP initialization, `tools/list`, or `get_system_stats` fails, the setup is
  not reported as connected even when the container is running.
- If Web UI submission is rejected, the validation payload and failing node are
  recorded; the queue is not retried repeatedly.
- If enabling host networking restarts Docker Desktop, existing containers are
  checked after restart. This change does not delete containers, volumes, or
  images.
- Unrelated dirty repository files remain untouched and uncommitted.

## Repository Changes

The implementation is expected to create or modify these bounded surfaces:

- `docker/comfyui-mcp/Dockerfile`
- `docker/comfyui-mcp/package.json`
- `docker/comfyui-mcp/package-lock.json`
- `docker/comfyui-mcp/compose.yml`
- `docker/comfyui-mcp/healthcheck.mjs`
- `docker/comfyui-mcp/smoke.mjs`
- `tests/python/test_comfyui_mcp_image_contract.py`
- `taskfiles/comfyui/taskfile.yml`
- `Taskfile.yml`
- `chezmoi/.chezmoidata/mcp_servers.yaml`
- the existing MCP template contract tests affected by the new Codex entry
- `docs/comfyui/mcp.md`

The native ComfyUI workflow and launch-service files are runtime dependencies,
not repository implementation files, and are not rewritten by this change.

## Test Strategy

Tests are written before implementation for:

- the exact Node image tag and digest;
- the exact MCP package version and lock-file presence;
- ARM64 image support;
- non-root, read-only, no-new-privileges runtime settings;
- host networking with no Compose `ports` publication;
- loopback-only MCP and ComfyUI URLs;
- a real MCP health check rather than a TCP-only probe;
- the unified Codex MCP declaration;
- Taskfile commands targeting only the dedicated Compose project;
- absence of Agent Panel, credentials, Docker socket, model mounts, and
  H3-specific service naming.

Repository validation runs the focused Python contract test, existing MCP
template tests, `docker compose config --quiet`, Docker image build, and final
diff review. Live validation then performs the health/MCP/Web UI acceptance
sequence above.

## Operational Entry Points

Taskfile owns the public command sequence. The operator receives tasks for:

- build or update the pinned image;
- start/recreate the MCP service;
- show status;
- follow logs;
- run the MCP live smoke test;
- stop the service without deleting persistent data.

Documentation explains the one-time Docker Desktop host-networking setting,
targeted Codex configuration apply, normal startup, safe shutdown, upgrades,
port conflicts, ComfyUI dependency failures, and the distinction between MCP
connectivity and a completed video render.

## Upstream References

- ComfyUI MCP: <https://github.com/artokun/comfyui-mcp>
- ComfyUI server routes:
  <https://docs.comfy.org/development/comfyui-server/comms_routes>
- Docker Desktop host networking:
  <https://docs.docker.com/engine/network/drivers/host/>
- Node.js current release: <https://nodejs.org/en/download/current/>
- Node.js official Docker image: <https://hub.docker.com/_/node>
