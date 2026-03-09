# Sandbox Hardening Design (Docker Engine Only)

Date: 2026-03-09

## Background

OpenClaw sandbox containers currently expose `DOCKER_HOST` to sandbox containers,
allowing sandbox escape via the host Docker daemon. This is the single largest
security vulnerability in the current setup. Additionally, documentation is out
of sync with actual configuration (e.g., `capAdd: ["SYS_ADMIN"]` references that
were already removed).

This design addresses sandbox hardening while staying within Docker Engine
(no Kubernetes migration).

## Constraints

- OpenClaw 2026.3.x: sandbox backend is Docker-only (no pluggable providers)
- OpenClaw sandbox config is a single profile (no per-task switching)
- Sandbox must support: Playwright CLI E2E, git push, gh CLI, pnpm install
- Gateway container retains Docker socket access (required for sandbox spawning)

## Decisions Made

| Decision                | Choice                     | Rationale                                                                                                                                     |
| ----------------------- | -------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| DOCKER_HOST             | Remove from sandbox        | Eliminates sandbox escape. docker build delegated to gateway.                                                                                 |
| Network                 | Keep `bridge`              | pnpm install + Playwright CLI require external access. Egress restriction not practical with Docker Engine alone (deferred to k8s migration). |
| GITHUB_TOKEN / GH_TOKEN | Keep in sandbox            | git push + gh CLI needed in sandbox. Fine-grained PAT limits blast radius.                                                                    |
| XAI_API_KEY             | Remove from sandbox        | Gateway-side web_search / Claude Code subagent handles Grok API.                                                                              |
| Playwright              | @playwright/cli only       | AI agent-oriented CLI. @playwright/test not used.                                                                                             |
| SYS_ADMIN               | Not needed                 | Playwright defaults to --no-sandbox (chromiumSandbox: false). capDrop: ALL is sufficient.                                                     |
| seccomp                 | Investigate, low priority  | capDrop: ALL already blocks dangerous syscalls via capability checks. Custom seccomp adds marginal value.                                     |
| Warm pools              | Not feasible               | OpenClaw controls sandbox creation internally. Docker Engine alone cannot pre-warm. Deferred to ISandboxProvider (Issue #12405) or k8s.       |
| Hibernate               | Not needed                 | Session idle (60min) + prune (24h/7d) is sufficient.                                                                                          |
| GC automation           | OpenClaw cron, 1h interval | Cleanup exited sandbox containers as safety net.                                                                                              |

## Changes

### 1. Remove DOCKER_HOST and XAI_API_KEY from sandbox env

**Files:**

- `chezmoi/dot_openclaw/openclaw.docker.json.tmpl`

**Before:**

```json
"env": {
  "DOCKER_HOST": "tcp://host.docker.internal:2375",
  "GITHUB_TOKEN": "@@GITHUB_TOKEN@@",
  "GH_TOKEN": "@@GITHUB_TOKEN@@",
  "XAI_API_KEY": "@@XAI_API_KEY@@",
  "PLAYWRIGHT_BROWSERS_PATH": "/root/.cache/ms-playwright",
  "GIT_CONFIG_COUNT": "1",
  "GIT_CONFIG_KEY_0": "url.https://x-access-token:@@GITHUB_TOKEN@@@github.com/.insteadOf",
  "GIT_CONFIG_VALUE_0": "https://github.com/"
}
```

**After:**

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

### 2. Update AGENTS.md sandbox rules

**File:** `docker/openclaw/AGENTS.md`

Remove:

- "sandbox 内で docker build + docker run" section (lines 454-481)
- `capAdd: ["SYS_ADMIN"]` references
- `shmSize: "256m"` references

Add/Update:

- Docker build/run is done on gateway side, not in sandbox
- Playwright CLI (@playwright/cli) works with capDrop: ALL (--no-sandbox is default)
- SYS_ADMIN is not required

### 3. Update 04-sandbox.md documentation

**File:** `docs/chezmoi/dot_openclaw/04-sandbox.md`

- Remove DOCKER_HOST, XAI_API_KEY from environment variables table
- Remove DOCKER_HOST socat proxy section from design decisions
- Update security notes to reflect that sandbox no longer has Docker daemon access
- Remove capAdd / shmSize from security considerations (already deleted from config)
- Add GC cron job documentation

### 4. Add sandbox:gc Taskfile task

**File:** `Taskfile.yml`

```yaml
sandbox:gc:
  desc: Remove exited sandbox containers (safety net for orphans)
  cmds:
    - bash -c 'ids=$(docker ps -aq --filter "ancestor=openclaw-sandbox-common:bookworm-slim" --filter "status=exited"); if [ -z "$ids" ]; then echo "No exited sandbox containers"; else echo "Removing $ids"; docker rm $ids; fi'
```

### 5. Add sandbox-gc cron job to OpenClaw

**File:** `chezmoi/dot_openclaw/cron/jobs.seed.json.tmpl`

Add a new cron job entry that runs every hour to clean up exited sandbox containers.

### 6. Investigate seccomp support (low priority)

Check if OpenClaw's `sandbox.docker` schema supports `securityOpt`.
If supported, create a custom seccomp profile blocking `ptrace`, `mount`, `unshare`.
If not supported, document the gap and defer.

## Security Impact

| Risk                                   | Before                                                    | After                                                 |
| -------------------------------------- | --------------------------------------------------------- | ----------------------------------------------------- |
| Sandbox escape via Docker daemon       | **Critical** -- DOCKER_HOST gives full host Docker access | **Eliminated** -- sandbox has no Docker access        |
| Host filesystem access                 | Possible via `docker run -v /:/host`                      | **Eliminated**                                        |
| Other container manipulation           | Possible via `docker stop/rm`                             | **Eliminated**                                        |
| Secret exfiltration via docker inspect | Possible                                                  | **Eliminated**                                        |
| Token leakage (GITHUB_TOKEN)           | Present                                                   | Present (acceptable: Fine-grained PAT, limited scope) |
| Network data exfiltration              | Possible (bridge)                                         | Possible (bridge) -- deferred to k8s migration        |

## Future Work (Deferred)

- **Network egress control**: Implement via k8s NetworkPolicy when migrating to kind + agent-sandbox
- **Warm pools**: Requires OpenClaw ISandboxProvider (Issue #12405) or k8s SandboxWarmPool CRD
- **seccomp profile**: Contingent on OpenClaw schema support
- **Sandbox image split**: Not useful until OpenClaw supports multiple sandbox images per profile
