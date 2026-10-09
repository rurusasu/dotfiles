# Retired Docker Hermes runtime

Hermes CLI, profile bootstrap, and the messaging gateway run natively under
Nix/Home Manager. `docker/hermes-service/compose.yml` defines only `chromium`,
`browser-mcp`, and `xapi-mcp`. It does not provide an Agent, Dashboard,
`hermes-bootstrap` service, or a Docker CLI backend.

The remaining runtime routes were audited and removed:

| Former route                                                                                                                                                                 | Current ownership                                                                                                                  |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `scripts/sh/hermes-agent.sh` Docker storage locks, volume seed/ownership, container secret-plan/apply, stack recovery, API readiness, gateway convergence, and image pruning | Removed; native `hermes-bootstrap.sh` and the Nix-managed `hermes-bootstrap` command apply profiles and secrets                    |
| `scripts/sh/hermes-docker.sh` container CLI                                                                                                                                  | Removed; use `hermes` or `task hermes:cli`                                                                                         |
| PowerShell `lib/HermesGateway.ps1` container gateway convergence                                                                                                             | Removed; `NixRebuildHandler` validates the native NixOS WSL service and CLI                                                        |
| Docker Agent/Dashboard tasks                                                                                                                                                 | Already absent; `task hermes:up`, `down`, `restart`, and `logs` operate the native gateway                                         |
| X API shell host helpers formerly sourced from `hermes-agent.sh`                                                                                                             | Preserved in `hermes-sidecar-common.sh`; OAuth, service-account cache, token sync/rotation, rollback, and restart remain supported |
| Browser and X API Compose routes                                                                                                                                             | Preserved; the X API `up` adapter names the three supported sidecars explicitly                                                    |

Tests for removed Docker Agent implementation details were removed with their
implementations. Native installer routing, X API authentication and token cache
contracts remain tested. PowerShell `HermesXApi.ps1` and the WSL native setup
handler retain their current responsibilities.

Deleting repository routes does not stop an existing container or remove any
Docker volume, profile, session, browser data, or credentials. An old `hermes`
container may still be running from a former Compose project. Its lifecycle and
data migration require an explicit operator decision and its original project
configuration; the current sidecar Compose project cannot manage that backend.
See [native bootstrap operations](bootstrap.md) for the migration boundary and
[Desktop operations](desktop.md) for the supported CLI/gateway entrypoints.
