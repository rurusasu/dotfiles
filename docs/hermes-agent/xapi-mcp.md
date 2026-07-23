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

Every managed distribution must own this non-secret configuration in its
`config.yaml`:

```yaml
mcp_servers:
  xapi:
    url: http://xapi-mcp:8080/mcp
    connect_timeout: 300
```

The bootstrap source contract validates this exact entry in the root
distribution and every managed profile. Bootstrap does not inject or merge it
into source repositories.

## First authentication

Set the X OAuth application credentials in the host environment. Do not put
them in Compose files, Git, or profile configuration:

```bash
export X_API_CLIENT_ID='...'
export X_API_CLIENT_SECRET='...'
task hermes:xapi:auth
```

The command runs X's documented headless OAuth flow. Complete the displayed
browser/code exchange once; subsequent service restarts reuse and refresh the
cache under `~/.hermes/.xurl`.

Start or recreate the stack after authentication:

```bash
task hermes:up
task hermes:xapi:logs
```

The normal bootstrap path also builds and starts `xapi-mcp`:

```bash
task hermes:bootstrap
```

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

