# Hermes Desktop and Agent

## Runtime ownership

The normal macOS `./install.sh` and NixOS `task nrs` flows install
and activate Hermes Agent through the Nix/Home Manager configuration. The
gateway is a native per-user service: systemd on Linux and launchd on macOS.
Use `task hermes:up`, `task hermes:down`, `task hermes:restart`, and
`task hermes:logs` to control that service through the Hermes CLI.

The Hermes Desktop application is installed separately. It does not make the
Docker Compose gateway the owner of the Agent runtime. The standard Hermes
setup does not start Docker, bootstrap a Docker gateway, or modify the existing
`hermes-data` volume.

The old Docker gateway tasks and backend have been removed. The old named
`hermes-data` volume is intentionally left untouched; Nix setup neither imports
nor deletes its contents.

The browser and MCP support containers remain separately available through
their dedicated Compose tasks; they are not the Hermes Agent runtime.
The [retired Docker runtime inventory](retired-docker-runtime.md) records the
removed adapters and the helpers retained by the current sidecars.

## Desktop installation and launch

`task hermes:desktop:install` verifies that the nix-darwin cask and Nix-managed
CLI are present; installation and repair belong to the Nix activation flow.
Launch the GUI with:

```bash
task hermes:desktop
```

The Desktop app's own backend/remote connection settings are separate from the
native messaging gateway service. Nix setup does not publish a Docker dashboard.

For the native CLI, use the Hermes command directly or pass arguments through
the Taskfile:

```bash
task hermes:cli -- --help
hermes gateway status
```

## Existing data and migration boundary

Hermes API keys, profiles, sessions, and memory remain in their current
runtime storage. Nix activation does not copy Docker volume contents into
`~/.hermes`, and it does not delete or rewrite that volume. If you want to move
legacy Docker data into the native runtime, that is a separate migration that
must be planned and verified before running; this setup intentionally leaves
both data stores untouched.
