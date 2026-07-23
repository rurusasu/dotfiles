# Hermes Chrome MCP For All Profiles

## Goal

Every Hermes source declared by `docker/hermes-agent/bootstrap-manifest.yaml`
must configure the visible container browser through the canonical Chrome MCP
endpoint:

```yaml
agent:
  disabled_toolsets:
    - browser
mcp_servers:
  chrome:
    url: http://browser-mcp:8080/mcp
    connect_timeout: 120
```

The requirement applies to the root distribution, every currently declared
named profile, and every profile added to the bootstrap manifest later. Hermes
profiles outside the manifest remain unmanaged and unchanged.

## Ownership

The root `config.yaml` remains owned by the `hermes-home` source distribution.
Each named profile's `config.yaml` remains owned by its corresponding
`hermes-profile-*` source distribution.

The dotfiles bootstrap validates this contract but does not inject, merge, or
rewrite MCP settings after applying a distribution. This preserves the existing
distribution ownership boundary and makes the responsible source repository
clear when validation fails. Every distribution manifest must list
`config.yaml` in `distribution_owned`, so the validated file is also the file
that bootstrap installs.

## Data Flow

1. Bootstrap reads the root and profile declarations from the manifest.
2. It fetches, verifies, and stages each declared source distribution.
3. Before starting the local transaction, it parses each staged `config.yaml`.
4. It verifies `config.yaml` ownership, the global built-in `browser`
   suppression, and the canonical `mcp_servers.chrome` URL and timeout.
5. Only after every declared source passes does bootstrap begin local writes.
6. The existing stack recreation flow restarts each gateway with the installed
   source-owned configuration.

Adding a profile to the manifest automatically adds its staged `config.yaml` to
the same validation path.

## Validation And Errors

Bootstrap rejects a declared source before local writes when:

- `config.yaml` is missing;
- `config.yaml` is absent from `distribution_owned`;
- the file is not valid YAML;
- `agent.disabled_toolsets` does not include `browser`;
- `mcp_servers` or `mcp_servers.chrome` is not a mapping;
- `mcp_servers.chrome.url` is not
  `http://browser-mcp:8080/mcp`; or
- `mcp_servers.chrome.connect_timeout` is not the integer `120`.

The error identifies the source and file without printing the full
configuration or any secret value. A failure prevents the transaction from
starting, so the root and every profile keep their previously installed state.

## Source Changes

The root source and every profile source declared by the current manifest must
carry the canonical block. At the time of this design, that covers:

- `rurusasu/hermes-home`;
- `rurusasu/hermes-profile-rick`;
- `rurusasu/hermes-profile-hoffman`;
- `rurusasu/hermes-profile-risarisa`; and
- `rurusasu/hermes-profile-nancy`.

Source changes must pass each repository's existing distribution validator
before bootstrap consumes them.

## Testing

Focused bootstrap tests cover:

- valid root and profile configurations;
- a missing `config.yaml`;
- malformed YAML;
- missing or non-mapping MCP sections;
- an incorrect Chrome MCP URL;
- an incorrect or non-integer timeout;
- validation before any local write; and
- automatic coverage of an additional manifest-declared profile;
- rejection when that future profile validates a file it does not distribute;
  and
- the static Compose contract connecting Browser MCP and noVNC to the same
  Chromium service and CDP process.

The full Hermes bootstrap and GitHub wrapper suites must remain green. Each
source repository must pass its own validator.

## Completion Criteria

After the source changes are available and bootstrap is applied locally:

1. The root profile and every manifest-declared named profile list `chrome` as
   an enabled MCP server.
2. Hermes reports the built-in `browser` toolset as disabled for every managed
   profile.
3. The Chrome MCP connection discovers the expected tools, including
   `navigate_page` and `take_snapshot`.
4. Nancy uses the Chrome MCP toolset rather than Hermes' built-in
   `browser_navigate` toolset.
5. A page opened by Nancy appears in the same Google Chrome session shown at
   `http://127.0.0.1:6080/`.
