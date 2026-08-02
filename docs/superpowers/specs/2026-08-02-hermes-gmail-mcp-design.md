# Hermes Gmail MCP OAuth Design

## Goal

Enable every managed Hermes profile to search and read Gmail threads and create
Gmail drafts from Discord-triggered agent conversations, while preventing send,
delete, and label-modification operations.

## Chosen architecture

Use Google's official remote Gmail MCP endpoint
`https://gmailmcp.googleapis.com/mcp/v1`. Hermes connects to it as an HTTP MCP
server using native OAuth PKCE. The existing Google Calendar OAuth client is
reused for the Gmail MCP client registration; Gmail authorization is a separate
consent because the existing Calendar refresh token does not imply Gmail
scopes.

The Hermes bootstrap copies the non-secret Gmail MCP configuration into the
root and every managed profile. The OAuth client ID and secret are derived from
the existing Calendar OAuth client JSON and exposed to each profile through
private environment values. Hermes persists the Gmail OAuth token cache in the
profile's own `mcp-tokens` directory, so each profile is verified independently.

## Allowed capability boundary

The Gmail MCP server is configured with an explicit native-tool allowlist:

- `search_threads`
- `get_thread`
- `get_message`
- `list_labels`
- `list_drafts`
- `create_draft`

The `gmail.readonly` and `gmail.compose` OAuth scopes are requested. Sending,
deleting, and label mutation are excluded from the Hermes tool registry and are
not part of the verification procedure.

## Login and verification

`task hermes:gmail:auth` performs one profile-at-a-time OAuth login with a
profile-specific `HERMES_HOME`. The operator completes Google's browser consent
flow; the command never prints or commits token contents. The task supports the
same host/Docker callback path as the pinned Hermes image and fails if no token
cache is written.

After login, every active managed profile is tested through its actual Discord
bot path. The verification asks the profile to search a harmless, narrow Gmail
query, retrieve one matching thread when available, list drafts, and create a
test draft addressed to `noreply@example.com` with a clearly marked test
subject. The test draft is never sent. A profile is successful only when the
Discord reply contains successful results for the MCP operations; local config
or `hermes mcp test` output alone is insufficient.

## Failure handling and security

- Missing OAuth consent, expired tokens, missing Gmail API/MCP API enablement,
  and callback failures are reported per profile without treating other
  profiles as representative.
- OAuth client values are never written to repository files or command-line
  arguments; only the existing 1Password-backed Calendar OAuth item is read.
- Gmail MCP tool discovery is filtered to the allowlist before agents can use
  it.
- The official Gmail MCP is a Developer Preview, so the implementation records
  that dependency in the Hermes documentation and validates the endpoint during
  bootstrap/runtime checks.

## Test strategy

Add contract tests before implementation for the Gmail MCP configuration,
OAuth environment derivation, profile propagation, tool allowlist, and auth
task command. Extend bootstrap unit/integration tests to prove every managed
profile receives the same non-secret MCP declaration and private OAuth client
environment values. Live OAuth and Discord tests remain an operator gate and
must run only after credentials and the Hermes stack are available.
