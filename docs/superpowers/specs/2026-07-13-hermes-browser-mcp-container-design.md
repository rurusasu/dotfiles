# Hermes Browser MCP Container Design

## Goal

Hermes Agent が、ホスト側の Chrome/Brave、Node.js、npm、Python、CDP ポート設定に依存せず、Docker 内の専用 Chromium を MCP 経由で操作できるようにする。

## Context

Hermes Agent は MCP サーバーを `config.yaml` から読み込み、別プロセスのブラウザ操作をツールとして利用できる。公式の WSL2 ガイドは Windows Chrome への接続に `chrome-devtools-mcp` を推奨しているが、この構成ではブラウザ自体もコンテナ化するため、ホストブラウザへの接続は行わない。

The browser automation feature and an actual Chrome extension are different concerns. This design provides isolated browser automation through Chrome DevTools MCP. Extension installation/management through Chrome DevTools MCP's pipe-only extension tools is not part of this change because the browser is accessed through a network CDP endpoint.

## Architecture

```text
Hermes Agent container
        |
        | Streamable HTTP: http://browser-mcp:8080/mcp
        v
Browser MCP container
  mcp-proxy 6.5.2
  chrome-devtools-mcp 1.4.0
        |
        | CDP: http://chromium:9222
        v
Dedicated Chromium container
  Debian + Chromium
  headless Chromium
  persistent /data browser profile
```

All three services share a private Compose network. No browser CDP or MCP port is published to the host. The only persistent browser state is a dedicated directory under the Hermes data directory, separate from the user's normal browser profile.

The MCP container converts the stdio transport of `chrome-devtools-mcp` to Streamable HTTP with `mcp-proxy`. Hermes connects to the stable internal service name `browser-mcp`, so the generated Hermes configuration contains no host paths or host executables.

## Components

### Chromium service

- Build a dedicated image from a pinned Debian family base and install Chromium inside the image.
- Run Chromium as a non-root user with `--headless=new`, `--remote-debugging-address=0.0.0.0`, and port `9222`.
- Store the browser profile at `/data`, mounted from `${HERMES_BROWSER_DATA_DIR:-${USERPROFILE:-${HOME}}/.hermes/.browser}`.
- Expose a Docker healthcheck through `/json/version`.
- Do not publish `9222` to the host.

### Browser MCP service

- Build a Node.js 22 image with exact npm dependencies:
  - `chrome-devtools-mcp@1.4.0`
  - `mcp-proxy@6.5.2`
- Start `chrome-devtools-mcp` with `--browser-url=http://chromium:9222` and `--no-usage-statistics`.
- Start `mcp-proxy` in Streamable HTTP mode on port `8080` and expose only `/mcp` to the Compose network.
- Wait for the Chromium healthcheck before starting.
- Do not mount the host filesystem or use host Node/npm/Python binaries.

### Hermes configuration

Extend the existing Hermes MCP configuration handler so every managed Hermes config receives:

```yaml
mcp_servers:
  browser:
    url: http://browser-mcp:8080/mcp
    connect_timeout: 120
```

The `browser` server is a handler-managed entry, alongside the existing X API entries. Existing unrelated MCP servers remain preserved. Managed profiles receive the same internal URL because they run in the root Hermes container and share its Docker network.

### Compose lifecycle

- `hermes:up` starts Hermes, Chromium, and Browser MCP through the existing Compose project.
- `hermes:down` removes all three services.
- `hermes:browser:*` Taskfile commands provide focused build, restart, logs, and status operations.
- Hermes depends on `browser-mcp` health, and Browser MCP depends on Chromium health.

## Security boundaries

- The browser has a disposable, dedicated profile and never receives the user's normal Chrome profile or cookies.
- CDP is reachable only inside the private Compose network.
- The MCP endpoint is reachable only by services on that network and is not published to `127.0.0.1`.
- Runtime logs are written to stderr/stdout as appropriate; MCP stdout remains reserved for protocol traffic inside the MCP process.
- Usage statistics are disabled for Chrome DevTools MCP.
- The MCP configuration does not expose Docker socket access, host paths, or host command execution.

## Failure handling

- If Chromium cannot start, its healthcheck stays unhealthy and Browser MCP does not start.
- If Browser MCP cannot connect to Chromium, Hermes reports the MCP connection failure while the browser container logs retain the CDP error.
- Restarting `browser-mcp` must not delete the persistent Chromium profile.
- Recreating the Compose project must preserve the browser profile while replacing only the containers.
- A direct `docker compose config` check must fail before startup when the Compose wiring is invalid.

## Testing and acceptance criteria

### Static tests

- PowerShell handler tests verify that `browser` is managed in Hermes `mcp_servers` without removing unrelated entries.
- PowerShell handler tests verify the Compose file declares `chromium` and `browser-mcp`, private networking, health dependencies, and no host CDP port publication.
- Dockerfile/package tests verify the exact MCP package versions and the internal CDP URL.
- Existing Hermes, chezmoi, and lifelog tests remain green.
- `git diff --check` and repository pre-commit checks remain green.

### Runtime smoke test

With Docker available:

1. `docker compose -f docker/hermes-agent/compose.yml config` succeeds.
2. The Chromium healthcheck becomes healthy.
3. Browser MCP can reach `http://chromium:9222/json/version`.
4. Hermes can complete an MCP initialize/list-tools exchange against `http://browser-mcp:8080/mcp`.
5. A browser MCP tool can open a public page and return its title or visible text.
6. No host-side `chromium`, `node`, `npm`, `python`, or CDP listener is required.
