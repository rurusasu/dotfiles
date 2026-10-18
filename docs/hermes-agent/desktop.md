# Hermes Desktop and Agent

## Runtime ownership

macOS `./install.sh`, NixOS/WSL `task nrs`, and standalone Linux Home Manager
flows install and activate Hermes Agent through the shared Home Manager
configuration. `task hermes:bootstrap` selects `nixos-rebuild` on NixOS and
`home-manager switch` on standalone Linux. The gateway is a native per-user
service: systemd on Linux and launchd on macOS.
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

On macOS, `desktop-darwin.nix` installs the official complete Apple Silicon
bundle through Nix. `nix/modules/ai_agents/hermes/sources.json` pins its URL and
SHA-512. The CLI and launchd gateway use the same bundle, including its Python
3.14 runtime and ready dependencies; Nix only extracts the archive and installs
launchers, without compiling Hermes or its native dependencies.
The signed app is preserved unchanged. Use Nix rebuilds for updates, rather
than the app's manual update button. The vendor disables unattended downloads
and installation, but its GUI still performs update checks.

The upstream Home Manager module continues to install Desktop on Linux,
including native NixOS, WSLg, and standalone Home Manager.
All platforms retain `~/.hermes` and the managed gateway configuration.
Windows does not install Hermes natively; Windows Task commands delegate to
the NixOS-WSL installation.
`task hermes:desktop:install` verifies the Desktop package and Nix-managed CLI.
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

On macOS, the former Python 3.12 build graph (including h5py, ONNX Runtime,
Torch and CTranslate2) is no longer required. Nix garbage collection can reclaim
unreferenced build dependencies after switching; retained generations may still
reference them. Do not delete store paths manually. Bootstrap shares the bundled
Python and current profile API. Nix's configuration merge helper still needs a
lightweight Python runtime, and shared tools such as Git and Node.js remain.
