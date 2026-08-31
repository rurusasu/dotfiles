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

| Account            | Vault      | Item               | Fields                                                                        |
| ------------------ | ---------- | ------------------ | ----------------------------------------------------------------------------- |
| `my.1password.com` | `openclaw` | `Hermes X API MCP` | `X_API_CLIENT_ID`, `X_API_CLIENT_SECRET`, `Refresh Token/X_API_REFRESH_TOKEN` |

Store the OAuth refresh token in the `Refresh Token` section of the same
1Password item. Do not store the short-lived access token or copy the complete
`.xurl/auth.yml` file:

The item name can be overridden per PC with
`DOTFILES_HERMES_XAPI_1PASSWORD_ITEM` or
`DOTFILES_HERMES_XAPI_OAUTH_ITEM`. Use separate OAuth items per PC only when
the X provider rotates refresh tokens; otherwise concurrent refreshes can
invalidate another PC's token. The default item is shared for environments
where the refresh token remains stable.

Then run the combined first-time setup. It performs OAuth authentication,
refresh-token synchronization to 1Password, and xapi-mcp restart in that
order:

```bash
task hermes:xapi:setup
```

The first step runs X's documented headless OAuth flow. After approving X,
the browser may show `localhost:8080` as unreachable. This is expected: copy
the complete callback URL from the address bar, or the requested code, into
the waiting terminal. Do not expose the internal MCP port. Unix hosts run the
bash adapter; Windows hosts run `scripts/powershell/hermes-xapi.ps1` and read
the same 1Password items through native `op.exe`.

For OAuth-only recovery or token rotation, run `task hermes:xapi:auth`; then
run `task hermes:xapi:sync-token` and `task hermes:xapi:restart` if you are not
using the combined setup task.

To copy the refresh token produced by the local xurl authentication into the
1Password field without printing it, run:

```bash
task hermes:xapi:sync-token
```

Existing local caches are preserved so a refresh-token rotation performed by
xurl is not overwritten by an older 1Password value. To intentionally
re-materialize the cache, set `DOTFILES_HERMES_XAPI_FORCE_CACHE_SYNC=1` for
that run.

Start or recreate the stack manually when using the atomic tasks:

```bash
task hermes:up
task hermes:xapi:logs
```

The normal bootstrap path also builds and starts `xapi-mcp`:

```bash
task hermes:bootstrap
```

This path uses the same 1Password-backed credential and refresh-token wrapper
as `task hermes:up` on Unix and Windows, so no `X_API_CLIENT_*` values need to
be exported before bootstrap.

## Verification

Check the service and test the same MCP endpoint from each profile:

```bash
docker compose -f docker/hermes-service/compose.yml ps xapi-mcp hermes
docker exec hermes hermes -p rick mcp test xapi
docker exec hermes hermes -p hoffman mcp test xapi
docker exec hermes hermes -p risarisa mcp test xapi
docker exec hermes hermes -p nancy mcp test xapi
```

If authentication is missing, inspect `task hermes:xapi:logs` and rerun
`task hermes:xapi:setup`. Never expose the internal MCP port or copy the
`.xurl` cache into a profile repository.
