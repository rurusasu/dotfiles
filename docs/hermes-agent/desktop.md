# Hermes Desktop and Agent

## Runtime ownership

The normal macOS `./install.sh --with-hermes` and NixOS `task nrs` flows install
and activate Hermes Agent through the Nix/Home Manager configuration. The
gateway is a native per-user service: systemd on Linux and launchd on macOS.
Use `task hermes:up`, `task hermes:down`, `task hermes:restart`, and
`task hermes:logs` to control that service through the Hermes CLI.

The Hermes Desktop application is installed separately. It does not make the
Docker Compose gateway the owner of the Agent runtime. The standard Hermes
setup does not start Docker, bootstrap a Docker gateway, or modify the existing
`hermes-data` volume.

## Explicit legacy Docker runtime

The Compose Agent remains available for existing users and data, but it is a
separate, opt-in legacy runtime. Start it only when explicitly needed:

```bash
task hermes:docker:up
task hermes:docker:logs
task hermes:docker:down
```

`task hermes:docker:down` stops only the gateway container; it does not remove
the Compose project or named volume. The existing volume name defaults to
`hermes-data` and can be overridden with `HERMES_DATA_VOLUME`. No volume
migration or deletion is performed by the Nix setup. The compatibility task
`task hermes:bootstrap` still invokes this legacy Docker bootstrap for existing
installer integrations; new normal setup flows must not call it.

The Docker Browser/MCP sidecars remain attached to that legacy Compose runtime.
They are not started by the native Nix/Home Manager service, and the native
setup does not require Docker Desktop.

## Desktop installation and launch

`task hermes:desktop:install` verifies that the nix-darwin cask and Nix-managed
CLI are present; installation and repair belong to the Nix activation flow.
Launch the GUI with:

```bash
task hermes:desktop
```

The Desktop app's own backend/remote connection settings are separate from the
native messaging gateway service. The Docker-only dashboard at
`http://127.0.0.1:9119` is available only when the legacy Docker gateway is
running; native Hermes setup does not publish that endpoint.

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
