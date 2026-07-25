# Hermes X API MCP

Hermes connects to X's official hosted MCP server through an isolated Compose
service. The service runs the official `@xdevplatform/xurl` bridge and exposes
it as Streamable HTTP inside the Compose network.

## Services

```text
Hermes profile config
  -> http://xapi-mcp:8080/mcp
  -> xapi-mcp container
  -> xurl mcp https://api.x.com/mcp
```

The `xapi-mcp` service uses the existing `hermes-browser` network and does not
publish port 8080 to the host. Its OAuth cache is the host runtime directory
`${HERMES_DATA_DIR:-~/.hermes}/.xurl`, mounted at `/root/.xurl`.

Every managed distribution must own `config.yaml`. During bootstrap, Hermes
installs this non-secret MCP entry into the staged runtime copy:

```yaml
mcp_servers:
  xapi:
    url: http://xapi-mcp:8080/mcp
    connect_timeout: 300
```

The bootstrap source contract still validates the source-owned Chrome MCP
guardrails, but X API MCP is synthesized in the staged runtime copy. Bootstrap
does not write the generated entry back to source repositories.

## First authentication

Create or update the X OAuth application credentials in 1Password. Do not put
them in Compose files, Git, profile configuration, Slack, or local env files:

| Account            | Vault      | Item               | Fields                                   |
| ------------------ | ---------- | ------------------ | ---------------------------------------- |
| `my.1password.com` | `openclaw` | `Hermes X API MCP` | `X_API_CLIENT_ID`, `X_API_CLIENT_SECRET` |

Then run the headless OAuth flow. The task reads those fields from 1Password
only for this explicit command:

```bash
task hermes:xapi:auth
```

The command runs X's documented headless OAuth flow. Complete the displayed
browser/code exchange once; subsequent service restarts reuse and refresh the
cache under `~/.hermes/.xurl`. Unix hosts run the bash adapter; Windows hosts
run `scripts/powershell/hermes-xapi.ps1` and read the same 1Password item
through native `op.exe`.

Start or recreate the stack after authentication:

```bash
task hermes:up
task hermes:xapi:logs
```

The normal bootstrap path also builds and starts `xapi-mcp`:

```bash
task hermes:bootstrap
```

This path uses the same 1Password-backed credential wrapper as
`task hermes:up` on Unix and Windows, so no `X_API_CLIENT_*` values need to be
exported before bootstrap.

## Verification

Check the service and test the same MCP endpoint from each profile:

```bash
docker compose -f docker/hermes-agent/compose.yml ps xapi-mcp hermes
docker exec hermes hermes -p rick mcp test xapi
docker exec hermes hermes -p hoffman mcp test xapi
docker exec hermes hermes -p risarisa mcp test xapi
docker exec hermes hermes -p nancy mcp test xapi
```

If authentication is missing, inspect `task hermes:xapi:logs` and rerun
`task hermes:xapi:auth`. Never expose the internal MCP port or copy the
`.xurl` cache into a profile repository.
