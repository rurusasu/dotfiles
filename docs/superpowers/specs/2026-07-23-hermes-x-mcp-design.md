# Hermes X MCP Integration Design

## Goal

Expose X's official hosted MCP server to every managed Hermes profile through a
dedicated Docker Compose service, while keeping X OAuth state and the Hermes
gateway lifecycle separate.

## Context and constraints

- The upstream MCP endpoint is `https://api.x.com/mcp`.
- The supported full-access connection is the `@xdevplatform/xurl` bridge,
  which handles OAuth 2.0 login, bearer-token injection, and token refresh.
- The Hermes gateway already runs in Docker and the Compose network is the
  correct private communication boundary for MCP services.
- Managed profiles own their declarative MCP configuration. The dotfiles
  bootstrap must not silently inject or merge profile configuration.
- X client credentials and the OAuth cache are runtime secrets. They must not
  be committed, embedded in images, or published as host ports.

## Decision

Add an `xapi-mcp` service to `docker/hermes-agent/compose.yml`. The service
will use a small Node image containing pinned `@xdevplatform/xurl` and
`mcp-proxy` dependencies. Its command will expose the xurl stdio bridge as
Streamable HTTP on `0.0.0.0:8080`; the service will not publish that port to
the host. Hermes will connect to `http://xapi-mcp:8080/mcp` over the existing
Compose network.

The service will bind-mount the existing host cache directory
`${HERMES_DATA_DIR}/.xurl` at `/root/.xurl` and receive `CLIENT_ID` and
`CLIENT_SECRET` from host environment variables via Compose interpolation.
The image will contain no credentials. A dedicated `task hermes:xapi:auth`
operation will provide the documented headless first-login flow; normal stack
startup will reuse the shared cache.

Every managed distribution (`default`, `rick`, `hoffman`, `risarisa`, and
`nancy`) will declare the same `mcp_servers.xapi` URL and a generous connection
timeout. The bootstrap source contract will validate this invariant so a
profile cannot silently lose X MCP access during a distribution update. The
actual profile repositories remain the owners of their `config.yaml` files.

## Alternatives considered

### Install xurl directly in the Hermes image

This avoids the HTTP proxy and is smaller initially, but every profile would
spawn its own bridge process inside the gateway container. It couples X
authentication and process lifecycle to Hermes image updates and makes the
shared-account behavior less explicit. It also conflicts with the requested
independent service boundary.

### Connect each profile directly to `https://api.x.com/mcp`

This can use a static app-only bearer header, but it is read-only and does not
provide the OAuth user-context capabilities needed for bookmarks, Articles,
or other account-scoped operations. It also duplicates credential wiring in
every profile.

## Runtime flow

```text
task hermes:xapi:auth (first run only)
  -> xapi-mcp container runs xurl OAuth2 headless flow
  -> ~/.hermes/.xurl receives the refreshed credential cache

task hermes:bootstrap / task hermes:up
  -> xapi-mcp starts independently
  -> xurl bridge connects to https://api.x.com/mcp
  -> mcp-proxy exposes http://xapi-mcp:8080/mcp
  -> every Hermes profile discovers the same X MCP tool set
```

## Error handling and security

- `xapi-mcp` has a TCP healthcheck and Hermes depends on it being healthy.
- Missing client credentials or an empty OAuth cache produce a clear service
  error; they do not fall back to an unauthenticated endpoint.
- The service is reachable only on the internal `hermes-browser` network.
- `.xurl` remains outside Git and is created by the existing Hermes runtime
  preparation helper.
- Compose and source-contract tests must reject host port publishing, secret
  values in committed configuration, and noncanonical profile URLs.

## Verification

- Unit/contract tests cover the Compose service, dependency, mount, healthcheck,
  command, and all-profile source contract.
- `docker compose -f docker/hermes-agent/compose.yml config --quiet` validates
  interpolation and Compose syntax.
- The pinned bootstrap test stage remains green.
- With Docker and valid X credentials available, `task hermes:xapi:auth`,
  `task hermes:up`, and `hermes mcp test xapi` are the runtime smoke path.

