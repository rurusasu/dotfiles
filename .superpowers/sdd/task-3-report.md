### Task 3 Report: Wire Chromium and Browser MCP into Hermes Compose

#### Summary

- Inspected the current Task 3 uncommitted diff against `.superpowers/sdd/task-3-brief.md`.
- No concrete Task 3 defects were found, so no implementation changes were made beyond this report.
- Verified the focused Hermes handler Pester test and Docker Compose rendering.

#### Files changed

- `docker/hermes-agent/compose.yml`
  - Adds `chromium` and `browser-mcp` services.
  - Connects `hermes`, `chromium`, and `browser-mcp` to the named `hermes-browser` bridge network.
  - Keeps only the existing Hermes API/dashboard host port mappings.
  - Adds health-ordered startup:
    - `hermes` depends on `browser-mcp` with `condition: service_healthy`.
    - `browser-mcp` depends on `chromium` with `condition: service_healthy`.
  - Configures Chromium profile bind mount from `${HERMES_BROWSER_DATA_DIR:-${USERPROFILE:-${HOME}}/.hermes/.browser}` to `/data`.
  - Sets Chromium `shm_size: 2g`.
  - Adds Chromium `/json/version` healthcheck and Browser MCP TCP 8080 healthcheck.
- `Taskfile.yml`
  - Updates `hermes:pull` to build `hermes chromium browser-mcp`.
  - Adds browser lifecycle tasks:
    - `hermes:browser:pull`
    - `hermes:browser:restart`
    - `hermes:browser:logs`
    - `hermes:browser:ps`
- `scripts/powershell/tests/handlers/Handler.HermesAgent.Tests.ps1`
  - Adds static assertions for the Compose browser wiring and Taskfile browser lifecycle tasks.
- `.superpowers/sdd/task-3-report.md`
  - Adds this completion report.

#### Commands and results

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path './scripts/powershell/tests/handlers/Handler.HermesAgent.Tests.ps1' -Output Detailed"
```

Result:

- Exit code: 0
- Pester v5.7.1
- Tests discovered: 52
- Tests passed: 52
- Tests failed: 0
- Tests skipped: 0

```powershell
docker compose -f docker/hermes-agent/compose.yml config
```

Result:

- Exit code: 0
- Compose rendered successfully.
- Rendered services include `hermes`, `chromium`, and `browser-mcp`.
- Rendered network is named `hermes-browser` with `driver: bridge`.
- Rendered published ports are only Hermes API/dashboard ports `8642` and `9119`.

#### Self-review

- Confirmed no host port mappings for browser CDP `9222` or Browser MCP `8080`.
- Confirmed only the existing Hermes API/dashboard ports remain published.
- Confirmed `hermes-browser` is a named bridge network and is not marked internal.
- Confirmed health-ordered dependencies match the brief.
- Confirmed Chromium profile source exactly matches the required nested fallback expression in source YAML.
- Confirmed Chromium target is `/data` and `shm_size` is `2g`.
- Confirmed Browser MCP healthcheck probes TCP 8080 and Chromium healthcheck uses `/json/version`.
- Confirmed `hermes:pull` builds `hermes chromium browser-mcp`.
- Confirmed browser pull/restart/logs/ps tasks exist.

#### Concerns

- Full repo test was intentionally not run, per task instruction.
- Compose validation renders the Chromium bind mount source with the current Windows profile fallback (`C:\Users\KoheiMiki/.hermes/.browser`), while the source YAML keeps the required portable nested fallback expression.
