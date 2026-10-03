# Hermes X API MCP

Native Hermes connects to X's official hosted MCP server through an independent
Compose sidecar. The sidecar runs the official `@xdevplatform/xurl` bridge and
exposes Streamable HTTP on loopback only.

## Services

```text
Hermes profile config
  -> http://127.0.0.1:8766/mcp
  -> xapi-mcp container
  -> xurl mcp https://api.x.com/mcp
```

The `xapi-mcp` service publishes port `8766` only on `127.0.0.1`. Its OAuth cache is the host runtime directory
`${HERMES_DATA_DIR:-~/.hermes}/.xurl`, mounted at `/root/.xurl`.

The shell lifecycle adapter loads `scripts/sh/hermes-sidecar-common.sh` for
host paths, the private 1Password service-account cache, OAuth credentials,
token validation, and refresh-token synchronization. It does not load or start
the retired Docker Agent/Dashboard. Windows uses `lib/HermesXApi.ps1` through
the matching PowerShell entrypoint. Both adapters preserve the local cache on
infrastructure failures and keep successfully rotated tokens if 1Password
synchronization fails.

Every managed distribution must own `config.yaml`. During bootstrap, Hermes
installs this non-secret MCP entry into the staged runtime copy:

```yaml
mcp_servers:
  xapi:
    url: http://127.0.0.1:8766/mcp
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

When an interactive agent has desktop/browser control, the agent owns this
browser handoff: open the generated X authorization URL, use the existing
1Password-backed browser login when needed, approve the requested access,
validate that the redirect targets `localhost:8080/callback` and contains the
expected OAuth `code` and `state`, and return the callback URL or code to the
waiting terminal without printing it. Ask the user to intervene only for a
provider-enforced human-presence step such as biometric/passkey confirmation,
2FA, CAPTCHA, or an account choice that cannot be inferred safely. For a direct
human-run session without an interactive agent, perform the same browser and
terminal handoff manually.

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

Normal stack startup validates the cached token with a one-shot `xurl token`
probe before recreating any long-running service. If validation fails, startup
atomically replaces the local cache from the 1Password refresh token and probes
exactly once more. A second failure stops before stack recreation and reports
`task hermes:xapi:setup` as the recovery command. The TCP healthcheck is only a
process/liveness signal and is not treated as proof that OAuth is valid.

Start or recreate the X API sidecar independently of the native Hermes gateway:

```bash
task hermes:xapi:restart
task hermes:xapi:logs
```

## Verification

Check the service and test the same MCP endpoint from each profile:

```bash
docker compose -f docker/hermes-service/compose.yml ps xapi-mcp
hermes -p rick mcp test xapi
hermes -p hoffman mcp test xapi
hermes -p risarisa mcp test xapi
hermes -p nancy mcp test xapi
```

If authentication is missing, inspect `task hermes:xapi:logs` and rerun
`task hermes:xapi:setup`. Never expose the internal MCP port or copy the
`.xurl` cache into a profile repository.
