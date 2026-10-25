# Hermes Distribution Ownership

`nix/modules/ai_agents/hermes/default.nix` directly imports the official Home
Manager module and declares services/settings. The module manages Agent,
Desktop on every supported OS, gateway, and root settings. LCM remains in
`extraPlugins`.

Named profiles use Git configuration sources as their canonical data; each
profile owns its individual secret references. Install with the official
`hermes profile install` command, supplying a Git URL or a local profile
directory, including a monorepo subdirectory. The distribution manifest's
`name` identifies the profile. Delegate later updates to `hermes profile update`.

Shared root MCP definitions use `programs.mcp.servers`, converted into the
official typed `services.hermes-agent.mcpServers` option. Named profiles do not
inherit root MCP settings; their Git configuration must reference the shared
gateway or the same remote URL.

A monorepo has not been created or migrated, and its URL is undecided.
Private-profile MCP migration and Pipedream OAuth setup have not been performed.

See [Hermes Operations](bootstrap.md), [Desktop and Agent](desktop.md), and
[Home/Profile Layout](profile-home-layout.md).
