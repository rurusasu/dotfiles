# Hermes Visible Browser Slack Registration Design

## Goal

Hermes Agent が Slack App 登録を browser tooling で最後まで進められるようにする。ログイン、2FA、Slack 側の確認画面など人間の介入が必要な場面では、ホスト PC から同じブラウザ画面を見て操作できるようにする。

## Context

現在の Hermes Browser MCP は、Compose 内の専用 Chromium と Browser MCP container だけを使う。CDP `9222` と Browser MCP `8080` は Compose network 内専用で、ホストには publish しない。これは host browser や host CDP endpoint に依存しないためにはよいが、Slack API のログイン画面で Hermes が止まったとき、ユーザーがその browser session に入れない。

Slack App は manifest UI または App Manifest API で作成できる。今回の目標は API token 前提の完全 API 化ではなく、Hermes が Slack UI を操作して app 作成、Socket Mode app-level token 生成、workspace install、profile `.env` 反映まで進めることに置く。Slack login / 2FA / consent は noVNC でユーザーが同じ session に介入できる。

Relevant Slack docs:

- Slack app manifests: https://docs.slack.dev/app-manifests/configuring-apps-with-app-manifests
- App Manifest API: https://docs.slack.dev/reference/methods/apps.manifest.create
- Socket Mode setup: https://docs.slack.dev/apis/events-api/using-socket-mode
- OAuth install flow: https://docs.slack.dev/authentication/installing-with-oauth

## Architecture

```text
Host PC
  http://127.0.0.1:${HERMES_BROWSER_VIEW_PORT:-6080}
        |
        | noVNC web UI
        v
Hermes Chromium container
  Xvfb display
  visible Chromium window
  x11vnc + noVNC/websockify
  CDP forwarder on 0.0.0.0:9222
        ^
        | CDP: http://chromium:9222
        |
Browser MCP container
  chrome-devtools-mcp
  mcp-proxy Streamable HTTP on 8080
        ^
        | http://browser-mcp:8080/mcp
        |
Hermes Agent container
```

Only the noVNC browser viewer is published to the host, and only on `127.0.0.1`. CDP `9222` and MCP `8080` remain private to the Compose network.

## Components

### Visible Chromium Runtime

`docker/hermes-browser` changes from headless Chromium to visible Chromium inside an X server:

- Install Chromium plus `xvfb`, `x11vnc`, `novnc`, and `websockify`.
- Run as the existing non-root `hermes-browser` user.
- Start `Xvfb` on a fixed display such as `:99`.
- Start Chromium without `--headless`, using the existing persistent `/data` user profile.
- Keep CDP on Chromium's loopback port, then keep the existing CDP forwarder on `0.0.0.0:9222` for Compose-only Browser MCP access.
- Start x11vnc against the Xvfb display, bound inside the container.
- Start noVNC/websockify on `6080`.
- Preserve stale Chromium singleton cleanup for the dedicated `/data` profile.

The entrypoint must treat Chromium as the primary process. If Chromium exits, the container exits so Docker restart policy can recover it.

### Compose Wiring

`docker/hermes-agent/compose.yml` keeps the existing three-service shape:

- `hermes`
- `chromium`
- `browser-mcp`

The `chromium` service additionally publishes:

```yaml
ports:
  - "127.0.0.1:${HERMES_BROWSER_VIEW_PORT:-6080}:6080"
```

It does not publish `9222`, `5900`, or `8080`. VNC remains an implementation detail behind noVNC.

### Taskfile and Operator UX

Existing tasks stay intact:

- `task hermes:browser:pull`
- `task hermes:browser:restart`
- `task hermes:browser:logs`
- `task hermes:browser:ps`

Add or document a simple status/open path:

- Browser viewer URL: `http://127.0.0.1:${HERMES_BROWSER_VIEW_PORT:-6080}`
- Dashboard URL remains `http://127.0.0.1:9119`

The setup success message can mention the browser viewer when Hermes Browser MCP is enabled.

### Slack Registration Workflow

Add a Hermes-facing registration guide under the managed Hermes docs, generated through the existing install handler path. The guide teaches Hermes to:

1. Locate the target profile directory, for example `/opt/data/profiles/nancy`.
2. Use the existing `slack-manifest.json`.
3. Open `https://api.slack.com/apps?new_app=1` with Browser MCP.
4. Choose app creation from manifest.
5. Paste the manifest.
6. Create or verify the Slack app.
7. Generate an app-level token with `connections:write` for Socket Mode.
8. Install the app to the workspace to obtain the bot token.
9. Write runtime credentials to the target profile `.env`:

```text
SLACK_BOT_TOKEN=xoxb-...
SLACK_APP_TOKEN=xapp-...
SLACK_ALLOWED_USERS=...
```

10. If 1Password is available and the user requests persistence there, update the matching `SlackBot-<ProfileTitle>` item instead of leaving the profile as the only source.

Hermes should pause and ask the user to use the noVNC URL whenever Slack requires login, 2FA, workspace selection, or consent that cannot be safely automated.

### Secret Handling

No token or secret is committed. The existing boundaries remain:

- Profile runtime secrets live in `~/.hermes/profiles/<profile>/.env`.
- Managed profile 1Password items follow `SlackBot-<ProfileTitle>`.
- The install handler may read or write non-secret docs and scripts.
- Generated tokens must never appear in logs, Git-tracked docs, or Slack status messages.

### Documentation

Update:

- `docs/hermes-agent/browser-mcp.md` to say noVNC is host-visible while CDP/MCP remain internal.
- `docs/chezmoi/secrets.md` to describe Slack app registration via Hermes browser and profile `.env` / 1Password storage.
- Handler-generated Hermes docs so Hermes itself sees the same guidance.

## Error Handling

- If noVNC starts but Chromium is unhealthy, the browser container stays unhealthy and Browser MCP does not start.
- If Slack login blocks automation, Hermes reports the noVNC URL and waits instead of retrying blindly.
- If token extraction from Slack UI fails, Hermes leaves a concise status message and does not write partial `.env` values.
- If `.env` already has Slack credentials, Hermes should ask before replacing them.
- If 1Password update fails, Hermes can still write the local profile `.env` after warning that persistent secret storage did not complete.

## Security Boundaries

- noVNC is bound to `127.0.0.1` on the host by default.
- VNC is not published to the host.
- CDP is not published to the host.
- Browser MCP is not published to the host.
- Chromium uses the dedicated Hermes browser profile, not the user's normal Chrome profile.
- The visible browser is a live automation surface; docs must warn that pages opened there are controlled by Hermes tools.

## Testing and Acceptance Criteria

### Static Tests

- Pester tests verify the Chromium image installs visible-browser dependencies.
- Pester tests verify the entrypoint starts Xvfb, Chromium, x11vnc, noVNC/websockify, and the CDP forwarder.
- Pester tests verify compose publishes only `127.0.0.1:${HERMES_BROWSER_VIEW_PORT:-6080}:6080` for browser viewing.
- Pester tests continue to verify `9222` and `8080` are not host-published.
- Pester tests verify generated docs mention the noVNC URL and Slack registration flow.

### Runtime Smoke Tests

With Docker available:

1. `docker compose -f docker/hermes-agent/compose.yml config` succeeds.
2. `task hermes:browser:pull` succeeds.
3. `task hermes:browser:restart` starts healthy `chromium` and `browser-mcp`.
4. `http://127.0.0.1:${HERMES_BROWSER_VIEW_PORT:-6080}` loads noVNC from the host.
5. Browser MCP can still initialize and list tools through `http://browser-mcp:8080/mcp`.
6. Browser MCP can open `https://api.slack.com/apps?new_app=1`, and the page is visible in noVNC.

### Manual Acceptance

- User can see Hermes browser activity from the host PC.
- User can complete Slack login or 2FA inside noVNC.
- Hermes can continue the same browser session after user intervention.
- For a test profile, Hermes can proceed from `slack-manifest.json` to created Slack app and profile Slack credentials without exposing secrets in Git.

## Out of Scope

- Publishing CDP to the host.
- Reusing the user's normal host Chrome profile.
- Making Slack login/2FA fully unattended.
- Replacing the existing Browser MCP transport.
- Committing or centrally storing generated Slack credentials without explicit user direction.
