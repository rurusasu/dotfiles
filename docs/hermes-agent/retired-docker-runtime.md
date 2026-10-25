# Retired Docker Hermes Runtime

The Hermes Agent and gateway use the official Nix/Home Manager module.
Chrome and X API MCP use shared native Home Manager services, each keeping one
stdio child behind `mcp-proxy`. Their loopback HTTP endpoints remain
`http://127.0.0.1:8765/mcp` and `http://127.0.0.1:8766/mcp`.
The former Browser/noVNC and X API Compose services, images and Docker-specific
lifecycle adapters have been removed. The native browser runs headless.

The former Docker Agent, Dashboard and custom bootstrap engine are retired.
Existing Docker volumes are not imported or deleted automatically. Preserve
sessions, credentials and local changes when planning any manual migration.
The existing `~/.hermes/.browser` browser profile and `~/.hermes/.xurl` OAuth
cache also remain in place. Native xurl reaches the cache through Home Manager's
`~/.xurl` and XDG configuration links, and conflicting existing paths stop
activation.

`MCP_DOCKER` is a separate shared MCP definition and remains available.
`docker/bootstrap-ci-tools` remains the CI tools image, and MLflow retains its
independent Compose configuration in `docker/local-ai-services`.

Use [Hermes Operations](bootstrap.md) and [Desktop operations](desktop.md).
