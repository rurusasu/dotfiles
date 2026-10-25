# Hermes Operations

The official Home Manager module manages the root settings, CLI, Desktop and
gateway through `nix/modules/ai_agents/hermes/default.nix`. Named profile
configuration is owned by its Git source, including profile-specific
1Password references.

Use the official profile commands:

```text
hermes profile install <source>
hermes profile update <name>
```

`<source>` is a Git URL or a local profile directory, including a profile
subdirectory in a monorepo. The distribution manifest's `name` identifies the
profile. Edit and commit configuration in its source repository.
The proposed monorepo has not been created or migrated, and its URL is
undecided.

| Task                                  | Behavior                                                                                      |
| ------------------------------------- | --------------------------------------------------------------------------------------------- |
| `hermes:bootstrap`                    | Apply Nix, then run `hermes:sync`                                                             |
| `hermes:sync`                         | Restart the gateway                                                                           |
| `hermes:profiles:sync PROFILE=<name>` | Run official profile update with `--force-config --yes`, replacing distribution configuration |
| `hermes:repository:sync`              | Pull/push existing lifelog commits with native Git                                            |

Clone, edit, commit and push profile sources with ordinary Git commands.

Root secret references use `settings.secrets.onepassword`; non-secret
environment settings use `home.sessionVariables`. Git uses the existing
1Password SSH configuration. This repository adds no profile-fetch activation
or custom profile synchronization engine.

Shared MCP definitions live in `nix/modules/ai_agents/mcp.nix` under
`programs.mcp.servers`: `MCP_DOCKER`, `chrome`, `xapi` and `pipedream`.
Codex uses its standard Home Manager integration; root Hermes converts the
shared definitions into the official typed `services.hermes-agent.mcpServers`.
Named Hermes profiles need the gateway reference or server URL in their own Git
configuration. Existing Chrome and X API entries keep the same loopback URLs;
profile-specific OAuth remains separate.

Chrome and X API MCP run as independent native Home Manager services:
`mcp-chrome` at `http://127.0.0.1:8765/mcp` and `mcp-xapi` at
`http://127.0.0.1:8766/mcp`. Each service uses `mcp-proxy` with one persistent
stdio child so clients share the browser profile and token cache safely. The
browser runs headless and needs no display or WSLg. Linux uses systemd user
services; macOS uses launchd agents.
`mcp-packages.nix` reuses the Chrome DevTools MCP package from the `mcp-servers`
input and builds xurl with `buildGoModule` from the upstream `xurl` source input.
xurl's version is derived from its source revision. Run
`nix flake update mcp-servers xurl` and apply Nix to update them.
The root browser profile and X API OAuth cache remain under the root Hermes
home. Windows X API tasks forward to the same native command in WSL.
`hermes:xapi:auth` stops `mcp-xapi` before authentication;
`hermes:xapi:sync-token` restarts it after successful token synchronization.

Start Desktop with `hermes-desktop`; inspect the gateway with
`hermes gateway status`. The official Darwin Nix output provides the launcher,
not an `.app` bundle.

See [1Password](onepassword.md), [Gmail MCP](gmail-mcp.md),
[Browser MCP](browser-mcp.md) and [X API MCP](xapi-mcp.md) for integrations.
Old Docker data is not migrated or deleted automatically; see the
[retired runtime note](retired-docker-runtime.md).
