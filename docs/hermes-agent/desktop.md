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

## Legacy task names

The gateway is no longer a Compose service. Existing Docker-prefixed task names
remain as compatibility aliases, but they control the native Nix-managed
gateway and do not start Docker:

```bash
task hermes:docker:up
task hermes:docker:logs
task hermes:docker:down
```

These aliases do not access or remove the old `hermes-data` volume. No volume
migration or deletion is performed by the Nix setup.

The browser and MCP support containers remain separately available through
their dedicated Compose tasks; they are not the Hermes Agent runtime.

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
