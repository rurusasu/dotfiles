# Hermes Browser MCP Container Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a fully containerized Chromium and Chrome DevTools MCP path that Hermes Agent can use without host Chrome, Node.js, npm, Python, or CDP dependencies.

**Architecture:** Extend the existing Hermes Compose project with a dedicated chromium service and a browser-mcp service. Chromium exposes CDP only on the Compose network; browser-mcp runs pinned chrome-devtools-mcp@1.4.0 behind pinned mcp-proxy@6.5.2 and exposes Streamable HTTP at http://browser-mcp:8080/mcp; the Hermes handler manages that URL in every root/profile config.yaml.

**Tech Stack:** Docker Compose, Debian Bookworm Chromium, Node.js 22, chrome-devtools-mcp@1.4.0, mcp-proxy@6.5.2, PowerShell/Pester, Taskfile.

## Global Constraints

- Runtime requires only Docker/Compose; no host Chromium, Chrome, Brave, Node.js, npm, Python, or CDP listener.
- Chromium CDP port 9222 and Browser MCP port 8080 are never published to the host.
- The browser profile is stored separately from the user's normal browser profile at `${HERMES_BROWSER_DATA_DIR:-${USERPROFILE:-${HOME}}/.hermes/.browser}`.
- chrome-devtools-mcp is pinned to 1.4.0; mcp-proxy is pinned to 6.5.2.
- MCP connects to http://chromium:9222; Hermes connects to http://browser-mcp:8080/mcp.
- The browser is headless and isolated; loading or managing a real host Chrome extension is out of scope for network CDP mode.
- Use 2-space YAML/JSON indentation and preserve existing Hermes handler behavior and unrelated MCP entries.
- Use task commit -- "message" for commits from the normal checkout; run the repository formatter and pre-commit checks before committing.

---

### Task 1: Add the dedicated Chromium image

**Files:**

- Create: docker/hermes-browser/Dockerfile
- Create: docker/hermes-browser/entrypoint.sh
- Test: scripts/powershell/tests/handlers/Handler.HermesAgent.Tests.ps1

**Interfaces:**

- Consumes: Compose bind mount at /data and the container network.
- Produces: A non-root Chromium process listening on 0.0.0.0:9222 with a healthcheckable /json/version endpoint.

- [ ] Step 1: Write static tests for the Chromium image contract

Add assertions that the repository contains docker/hermes-browser/Dockerfile and entrypoint.sh, the image installs Chromium, the entrypoint uses --headless=new, --remote-debugging-address=0.0.0.0, --remote-debugging-port=9222, and /data, and the service does not require a host Chrome executable.

- [ ] Step 2: Run the focused test to verify the new assertions fail

Run:

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path './scripts/powershell/tests/handlers/Handler.HermesAgent.Tests.ps1' -Output Detailed"
```

Expected: the new Chromium image assertions fail because the two files do not exist yet.

- [ ] Step 3: Implement the Chromium image

Create docker/hermes-browser/Dockerfile with a Debian Bookworm slim base, install chromium and curl, create a hermes-browser user, copy the entrypoint, and run as that user. Create entrypoint.sh with:

```sh
#!/bin/sh
set -eu

mkdir -p /data
exec /usr/bin/chromium \
  --headless=new \
  --disable-gpu \
  --remote-debugging-address=0.0.0.0 \
  --remote-debugging-port=9222 \
  --user-data-dir=/data \
  about:blank
```

The Dockerfile must install packages with --no-install-recommends, remove apt lists, mark the entrypoint executable, and keep Chromium non-root without --no-sandbox.

- [ ] Step 4: Run the focused test to verify the image contract passes

Run the Pester command from Step 2. Expected: the Chromium image assertions pass.

- [ ] Step 5: Commit the self-contained image change

Stage only the Chromium image and its static tests, then run:

```powershell
task commit -- "add isolated Chromium browser image"
```

Expected: formatter, pre-commit, and PowerShell tests pass and a commit is created.

### Task 2: Add the containerized Browser MCP server

**Files:**

- Create: docker/hermes-browser-mcp/Dockerfile
- Create: docker/hermes-browser-mcp/package.json
- Create: docker/hermes-browser-mcp/package-lock.json
- Test: scripts/powershell/tests/handlers/Handler.HermesAgent.Tests.ps1

**Interfaces:**

- Consumes: http://chromium:9222 on the Compose network.
- Produces: Streamable HTTP MCP at port 8080, path /mcp, with no host process dependencies.

- [ ] Step 1: Write static tests for the Browser MCP image contract

Add assertions that package.json pins:

```json
{
  "dependencies": {
    "chrome-devtools-mcp": "1.4.0",
    "mcp-proxy": "6.5.2"
  }
}
```

Also assert that the Dockerfile uses Node.js 22, installs with npm ci, disables update checks/statistics, starts mcp-proxy in stream mode on port 8080, and passes --browser-url=http://chromium:9222 and --no-usage-statistics to Chrome DevTools MCP.

- [ ] Step 2: Run the focused test to verify the new assertions fail

Run the Hermes Agent Pester file. Expected: the new Browser MCP assertions fail because the image files do not exist yet.

- [ ] Step 3: Implement and lock the Browser MCP image

Create package.json with the exact dependencies above and generate its lockfile with npm. Create a Node.js 22 Bookworm slim Dockerfile that copies both files, runs npm ci --omit=dev, sets CHROME_DEVTOOLS_MCP_NO_UPDATE_CHECKS=1, switches to the non-root node user, and starts:

```text
node_modules/.bin/mcp-proxy --server stream --port 8080 -- node_modules/.bin/chrome-devtools-mcp --browser-url=http://chromium:9222 --no-usage-statistics
```

Keep MCP protocol data on the child process stdout and send diagnostics to stderr. Add a TCP healthcheck for port 8080.

- [ ] Step 4: Run the focused test to verify the Browser MCP contract passes

Run the Hermes Agent Pester file. Expected: the new Browser MCP assertions pass.

- [ ] Step 5: Commit the self-contained Browser MCP image change

```powershell
task commit -- "add isolated Chrome DevTools MCP container"
```

Expected: formatter, pre-commit, and PowerShell tests pass and a commit is created.

### Task 3: Wire Chromium and Browser MCP into Hermes Compose

**Files:**

- Modify: docker/hermes-agent/compose.yml
- Modify: scripts/powershell/tests/handlers/Handler.HermesAgent.Tests.ps1
- Modify: Taskfile.yml

**Interfaces:**

- Consumes: the two images from Tasks 1 and 2.
- Produces: hermes, chromium, and browser-mcp services on one non-published Compose network with health-ordered startup.

- [ ] Step 1: Write failing Compose and Taskfile tests

Add assertions that compose.yml contains services named chromium and browser-mcp, a shared hermes-browser network, depends_on health conditions, a bind mount to /data using HERMES_BROWSER_DATA_DIR with the .hermes/.browser fallback, shm_size: 2g, and no 9222:9222 or 8080:8080 host port mapping. Add Taskfile assertions for hermes:browser:pull, hermes:browser:restart, hermes:browser:logs, and hermes:browser:ps.

- [ ] Step 2: Run the focused test to verify the new Compose assertions fail

Run the Hermes Agent Pester file. Expected: the new service/task assertions fail before the Compose changes exist.

- [ ] Step 3: Add the services and lifecycle tasks

Update docker/hermes-agent/compose.yml so hermes depends on browser-mcp health, browser-mcp depends on chromium health, all three services join hermes-browser, and only the existing Hermes API/dashboard ports remain published. Chromium uses the dedicated bind mount and shm_size: 2g. Use healthchecks for Chromium /json/version and Browser MCP TCP port 8080.

Do not mark the network internal because Chromium must browse public URLs. Keep both CDP and MCP ports unpublished and attach only the three services to the named bridge network. Update hermes:pull to build hermes, chromium, and browser-mcp, and add focused browser pull/restart/logs/status tasks.

- [ ] Step 4: Validate Compose syntax and static tests

Run:

```powershell
docker compose -f docker/hermes-agent/compose.yml config
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path './scripts/powershell/tests/handlers/Handler.HermesAgent.Tests.ps1' -Output Detailed"
```

Expected: Compose renders successfully and the new assertions pass.

- [ ] Step 5: Commit the Compose lifecycle change

```powershell
task commit -- "wire isolated browser services into Hermes compose"
```

Expected: formatter, pre-commit, and PowerShell tests pass and a commit is created.

### Task 4: Manage the Browser MCP URL in Hermes configurations

**Files:**

- Modify: scripts/powershell/handlers/Handler.HermesAgent.ps1
- Modify: scripts/powershell/tests/handlers/Handler.HermesAgent.Tests.ps1
- Modify: docs/chezmoi/secrets.md
- Create: docs/hermes-agent/browser-mcp.md

**Interfaces:**

- Consumes: the browser-mcp Compose service name.
- Produces: a managed browser MCP entry in root and managed profile Hermes configs.

- [ ] Step 1: Write the failing handler test

Add an Apply test with an existing config containing an unrelated local MCP server. Assert that the resulting config contains:

```yaml
browser:
  url: http://browser-mcp:8080/mcp
  connect_timeout: 120
```

and still contains the unrelated local server. Add a second assertion that rerunning Apply replaces a stale browser block instead of duplicating it.

- [ ] Step 2: Run the focused test to verify it fails

Run the Hermes Agent Pester file. Expected: the new browser configuration assertions fail because the handler currently manages only github, xapi, and x-docs.

- [ ] Step 3: Extend the handler minimally

In SetMcpConfigLines, add browser to the managed server names and append this exact desired block after the X docs block:

```powershell
"  browser:",
"    url: http://browser-mcp:8080/mcp",
"    connect_timeout: 120"
```

Keep existing unrelated-server preservation logic unchanged. Document the container-only browser path, the internal URL, the dedicated profile location, and the command sequence task hermes:pull then task hermes:up in docs/hermes-agent/browser-mcp.md; link it from the Hermes section in docs/chezmoi/secrets.md.

- [ ] Step 4: Run the focused test to verify it passes

Run the Hermes Agent Pester file. Expected: all existing tests plus the browser configuration tests pass.

- [ ] Step 5: Commit the handler and documentation change

```powershell
task commit -- "configure Hermes browser MCP endpoint"
```

Expected: formatter, pre-commit, and PowerShell tests pass and a commit is created.

### Task 5: Run full verification and container smoke tests

**Files:**

- Modify: none unless verification exposes a defect.

**Interfaces:**

- Consumes: all changes from Tasks 1–4.
- Produces: evidence that the isolated browser path starts and completes an MCP handshake.

- [ ] Step 1: Run repository static checks

Run:

```powershell
git diff --check
git grep -n -i openclaw -- ':!*.lock'
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path './scripts/powershell/tests/handlers/Handler.HermesAgent.Tests.ps1' -Output Normal"
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path './scripts/powershell/tests/chezmoi/ChezmoiTemplate.Tests.ps1' -Output Normal"
```

Expected: no OpenClaw matches, no diff errors, and all selected tests pass.

- [ ] Step 2: Build and start the isolated browser services

Run:

```powershell
docker compose -f docker/hermes-agent/compose.yml build chromium browser-mcp
docker compose -f docker/hermes-agent/compose.yml up -d chromium browser-mcp
docker compose -f docker/hermes-agent/compose.yml ps
```

Expected: Chromium and Browser MCP are healthy; no host port is allocated for 9222 or 8080.

- [ ] Step 3: Verify CDP reachability only over the Compose network

Run:

```powershell
docker compose -f docker/hermes-agent/compose.yml exec -T chromium curl -fsS http://127.0.0.1:9222/json/version
docker compose -f docker/hermes-agent/compose.yml exec -T browser-mcp node -e "fetch('http://chromium:9222/json/version').then(r => r.ok ? process.exit(0) : process.exit(1)).catch(() => process.exit(1))"
```

Expected: both commands exit successfully; a host request to 127.0.0.1:9222 is not required and is not a prerequisite.

- [ ] Step 4: Verify the MCP HTTP endpoint and Hermes startup

Start Hermes with docker compose -f docker/hermes-agent/compose.yml up -d hermes, inspect the Hermes logs, and run the configured MCP test path. Verify that the root and any existing managed profile config contains the internal browser URL, and that the MCP server reports a tools list containing browser navigation tools.

- [ ] Step 5: Stop services and verify profile persistence

Run:

```powershell
docker compose -f docker/hermes-agent/compose.yml down
docker compose -f docker/hermes-agent/compose.yml up -d chromium browser-mcp
docker compose -f docker/hermes-agent/compose.yml ps
```

Expected: the browser profile mount remains present and Chromium/Browser MCP become healthy again without host browser state.

- [ ] Step 6: Final verification before handoff

Run git status --short --branch, git diff --check, and the full relevant repository test task. Report the exact test counts and any runtime smoke limitation if Docker is unavailable.
