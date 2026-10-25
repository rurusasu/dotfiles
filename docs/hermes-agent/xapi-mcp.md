# Hermes X API MCP

Codex and root Hermes connect to the shared native `mcp-xapi` service at
`http://127.0.0.1:8766/mcp`. Home Manager runs Nix's `mcp-proxy` with one
persistent `hermes-xapi mcp` stdio child. That command validates the shared
OAuth cache and runs the official `xurl mcp https://api.x.com/mcp` bridge.

## Configuration and credentials

The shared `xapi` definition in
[`nix/modules/ai_agents/mcp.nix`](../../nix/modules/ai_agents/mcp.nix) supplies
both clients with this HTTP URL. The `mcp-xapi` service sets `HERMES_DATA_DIR`
to the root Hermes home and owns the command's lifetime. It runs as a systemd
user service on Linux/WSL and a launchd agent on macOS, listening on loopback
only. Clients share one xurl process so token rotation is not performed by
independent MCP children using the same cache.

[`mcp-packages.nix`](../../nix/modules/ai_agents/mcp-packages.nix) builds xurl
with `buildGoModule` from the upstream `github:xdevplatform/xurl` source pinned
by the non-flake `xurl` input. Its version comes from the source revision.
Update it with `nix flake update xurl`, then apply the usual Nix
configuration.

xurl uses the fixed native path `~/.xurl`. Home Manager connects it to the
existing private cache through these links:

```text
~/.xurl -> <XDG_CONFIG_HOME>/xurl -> <root Hermes home>/.xurl
```

The default cache remains `~/.hermes/.xurl/auth.yml`. Home Manager stops on
conflicting existing files or directories; it does not overwrite an independent
`~/.xurl` directory. Preserve that directory and resolve the conflict before
activation. Browser profiles, OAuth data and legacy Docker volumes are not
deleted by this migration.

The shell adapter uses `scripts/sh/hermes-xapi-common.sh` for 1Password
credentials, private service-account caching, token validation and refresh-token
synchronization. Windows tasks forward to the same native command in WSL, so
authentication and MCP use the same Linux root cache. Initial interactive
`hermes:xapi:auth` / `setup` can use the Windows `op.exe` bridge to populate
the root `.op.env` Service Account cache. The running service always selects
Nix's native `op` on every OS and reads 1Password items with the cached
`OP_SERVICE_ACCOUNT_TOKEN`; Windows PATH and interop are not needed by the
service. Named Hermes profiles
need a gateway reference or the following URL in their own Git source; root MCP
settings are not inherited. Existing entries with this URL remain valid.

```yaml
mcp_servers:
  xapi:
    url: http://127.0.0.1:8766/mcp
```

## First authentication

Create or update the X OAuth application credentials in 1Password. Keep the
values out of Git, profile configuration and local env files:

| Account            | Vault      | Item               | Fields                                                                        |
| ------------------ | ---------- | ------------------ | ----------------------------------------------------------------------------- |
| `my.1password.com` | `openclaw` | `Hermes X API MCP` | `X_API_CLIENT_ID`, `X_API_CLIENT_SECRET`, `Refresh Token/X_API_REFRESH_TOKEN` |

Store the OAuth refresh token in the `Refresh Token` section of the same item.
Do not store the short-lived access token or copy the complete `.xurl/auth.yml`
file. The item name can be overridden per PC with
`DOTFILES_HERMES_XAPI_1PASSWORD_ITEM` or `DOTFILES_HERMES_XAPI_OAUTH_ITEM`.
Use separate items per PC if the provider rotates refresh tokens in a way that
invalidates another PC's token.

Run the combined first-time setup. It stops `mcp-xapi`, authenticates,
synchronizes the refresh token to 1Password, and restarts the service:

```bash
task hermes:xapi:setup
```

The first step uses the headless OAuth flow. After approving X, the browser may
show `localhost:8080` as unreachable. Copy the complete callback URL from the
address bar, or the requested code, into the waiting terminal. Unix hosts run
the native command; Windows forwards it into WSL and uses its configured
1Password integration.

When an interactive agent has browser control, open the generated authorization
URL, use the existing login, approve access, validate that the redirect targets
`localhost:8080/callback` with the expected OAuth `code` and `state`, and return
the callback URL or code to the waiting terminal without printing it. Ask the
user to perform provider-required biometric/passkey confirmation, 2FA, CAPTCHA
or an account choice that cannot be inferred. In a human-run session, perform
the same handoff manually.

For OAuth-only recovery or token rotation, run:

```bash
task hermes:xapi:auth
task hermes:xapi:sync-token
```

`hermes:xapi:auth` stops the native service before interactive authentication,
and leaves it stopped until `hermes:xapi:sync-token` succeeds. This prevents
the service from refreshing the same cache during authentication. On Windows,
both tasks run through WSL. Reconnect the client's MCP session after the
service restarts.

Existing caches are preserved so a refresh-token rotation performed by xurl is
not overwritten by an older 1Password value. To intentionally re-materialize
the cache, set `DOTFILES_HERMES_XAPI_FORCE_CACHE_SYNC=1` for that run.

Each service startup runs `hermes-xapi mcp` and probes the cached token with `xurl token`. An
OAuth failure triggers one refresh from 1Password and one more probe. Repeated
OAuth failure stops startup and reports `task hermes:xapi:setup` as the recovery
command. Infrastructure failures restore the previous cache; a successful token
rotation is kept if the subsequent 1Password synchronization fails.

## Verification

On Linux/WSL, inspect or restart the native service with:

```bash
systemctl --user status mcp-xapi.service
journalctl --user -u mcp-xapi.service
systemctl --user restart mcp-xapi.service
```

On macOS, inspect the agent with
`launchctl print "gui/$(id -u)/org.nix-community.home.mcp-xapi"` and restart a
loaded agent with
`launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.mcp-xapi"`.
`hermes:xapi:sync-token` also bootstraps the agent if it was unloaded for
authentication. macOS logs are written to `mcp-xapi.log` in the root Hermes home.

After applying Nix/Home Manager and authenticating, test the root MCP endpoint:

```bash
hermes mcp test xapi
```

Test a named profile after updating its own MCP configuration:

```bash
hermes -p <name> mcp test xapi
```

If authentication is missing, inspect the service log and rerun
`task hermes:xapi:setup`. Keep the `.xurl` cache out of profile repositories.
