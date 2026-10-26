# Hermes Desktop and Agent

## Installation and launch

`nix/modules/ai_agents/hermes/default.nix` imports the official Home Manager
module and declares `services.hermes-agent` settings. The official module owns
the Agent package, Desktop application, and native gateway service
(systemd on Linux, launchd on macOS). Desktop is enabled on all supported OSes.
`settings.gateway.multiplex_profiles = null` clears a previous explicit value
and restores the upstream AUTO safety decision at gateway startup.

The root provider and default model are declared in
`services.hermes-agent.settings.model`: `openai-codex` and `gpt-6.1-sol`.
Hermes keeps its OAuth credentials in its private runtime auth store. In a
Home Manager installation, the model picker may authenticate successfully but
refuse to save the default model; update the Nix settings and apply them instead.
An unset model can fail local-session policy validation as `storage_unavailable`.

Apply the usual Nix/Home Manager configuration, then launch Desktop:

```bash
hermes-desktop
hermes gateway status
```

The official Darwin Nix output has no `.app` bundle; use `hermes-desktop`.
Windows uses the NixOS/WSL installation. The external LCM plugin is supplied
through `extraPlugins = [ inputs.hermes-lcm ]` because it is not bundled with Hermes.
Update its source with `nix flake update hermes-lcm`.
Hermes root settings convert the shared `programs.mcp.servers` definitions in
`nix/modules/ai_agents/mcp.nix` into the official typed
`services.hermes-agent.mcpServers` option.

## Profiles

Home Manager manages root settings. Each named profile's Git source owns its
`config.yaml` and individual `op://` references. Use the official
`hermes profile install <source>` command with a Git URL or a local profile
directory, including a profile subdirectory in a local monorepo. The installer
uses `manifest.name`; subsequent updates use `hermes profile update`.
Named profiles do not inherit root MCP settings. Their Git configuration must
reference the shared gateway or declare the corresponding MCP server URL.
The Chrome and X API loopback URLs are unchanged by the native service migration.

```bash
hermes profile install --help
hermes profile update --help
```

A shared profile monorepo has not been created or migrated; its URL is undecided.
Git uses the existing SSH configuration. See [1Password](onepassword.md) for
secret references and Pipedream OAuth.

## Runtime data

Hermes `.env`, authentication, sessions, and memory remain in their current
storage. Chrome and X API MCP run as shared native `mcp-chrome` and `mcp-xapi`
services, independent of the Hermes gateway. Clients connect to their loopback
HTTP endpoints; each service keeps one stdio child. Chrome runs headless using
the root Hermes `.browser` profile; native xurl accesses
the existing root `.xurl` cache through Home Manager's `~/.xurl` and XDG links.
Conflicting existing xurl paths stop activation. Legacy Docker data is not
migrated or deleted automatically; see the
[retired runtime inventory](retired-docker-runtime.md).
