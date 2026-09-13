# Docker MCP Toolkit shared profile design

## Goal

Issue #612 の MCP 変更として、Docker MCP Toolkit を共通 MCP の実行・認証・ライフサイクル管理基盤にする。Codex、Cursor、Gemini、VS Code、Windsurf、Zed は個別サーバーを重複定義せず、同じ `MCP_DOCKER` gateway へ接続する。

## Decisions

### Toolkit profile

The managed profile ID is `dotfiles`. The profile is converged locally by the public task `task mcp:toolkit:sync`, published to the default private GHCR OCI reference `ghcr.io/rurusasu/dotfiles/mcp-profile:latest` by `task mcp:toolkit:push`, and retrieved on another machine by `task mcp:toolkit:pull`. `MCP_TOOLKIT_PROFILE_REF` overrides the reference for versioned tags or another OCI registry. The profile is not silently created during ordinary chezmoi rendering. This keeps a core-only installation usable when Docker Desktop is not installed or not running.

The profile contains these Docker MCP Catalog entries:

| Logical server    | Toolkit source                                     | Reason                                    |
| ----------------- | -------------------------------------------------- | ----------------------------------------- |
| `context7`        | `catalog://mcp/docker-mcp-catalog/context7`        | Official remote catalog entry             |
| `deepwiki`        | `catalog://mcp/docker-mcp-catalog/deepwiki`        | Official remote catalog entry             |
| `exa`             | `catalog://mcp/docker-mcp-catalog/exa`             | Official container image                  |
| `firecrawl`       | `catalog://mcp/docker-mcp-catalog/firecrawl`       | Official container image                  |
| `github-official` | `catalog://mcp/docker-mcp-catalog/github-official` | Replaces the older archived GitHub image  |
| `obsidian`        | `catalog://mcp/docker-mcp-catalog/obsidian`        | Containerized Obsidian Local REST API MCP |
| `playwright`      | `catalog://mcp/docker-mcp-catalog/playwright`      | Official container image                  |
| `tavily`          | `catalog://mcp/docker-mcp-catalog/tavily`          | Official container image                  |

Hindsight remains a shared direct MCP entry at `http://127.0.0.1:8888/mcp/codex-shared/`. Docker MCP Gateway rejects local HTTP remotes as unsafe, so it cannot be placed in the Toolkit profile without introducing a separate bridge container. The existing Hindsight service lifecycle is still owned by `task hindsight:*`.

The user-requested removals `linear`, `sentry`, `cloud-run`, `superlocalmemory`, and `qmd` are removed from both the direct MCP data and the Toolkit profile. `plane`, `drawio`, and `kaggle` remain direct MCP entries because the current Docker catalog does not provide entries for them. These direct entries keep their existing support matrix to avoid reintroducing Codex startup failures from optional or authenticated servers.

### Client configuration

Each managed client gets one gateway entry:

```text
command = docker
args = ["mcp", "gateway", "run", "--profile", "dotfiles"]
```

Client templates continue to emit direct entries only for MCPs that remain outside Toolkit. Windows Codex uses the existing Docker readiness wrapper; other clients call the Docker CLI directly. The existing project `.mcp.json` also points at the gateway and retains only the unsupported direct `drawio` entry.

The Docker Toolkit client-connect command is used as the compatibility reference for Codex, Cursor, Gemini, VS Code, and Zed. Windsurf receives the same stdio gateway definition through its existing managed template. Unix and Windows VS Code/Zed deployment scripts both receive the gateway entry. Hindsight is emitted as a direct URL entry for every client, and the project `.mcp.json` keeps that direct entry as well.

### Secrets

Toolkit-managed secrets are stored in Docker Desktop's secret store, not in generated client files, the OCI profile artifact, or Git. `mcp_servers.yaml` stores only the non-secret 1Password references for the currently available `openclaw` vault items. `task mcp:toolkit:secrets` reads those references at runtime and pipes each value to Docker MCP Toolkit over standard input. The expected secret names are:

```text
context7.api_key
exa.api_key
firecrawl.api_key
github.personal_access_token
obsidian.api_key
tavily.api_token
```

The configured references use account `my.1password.com` and vault `openclaw`. Context7 and Obsidian remain documented as unavailable until matching items are created in that vault; no unrelated `Private` item is substituted. No template-time secret materialization is introduced for Toolkit.

### Obsidian

The Docker catalog `mcp/obsidian` is used. It requires the Obsidian Local REST API community plugin and API key, and the container connects to the host plugin endpoint. This intentionally differs from the article's direct filesystem `obsidian-mcp` process: the Toolkit profile is the source of lifecycle and credential management.

### Hermes

Hermes's Browser MCP, X API MCP, Gmail MCP, and Calendar MCP remain Hermes-container/profile-owned services. They are not exposed through the host Docker MCP Toolkit profile because their endpoints and credentials are intentionally internal to the Hermes Compose network. Hindsight is the shared exception because it already exposes a host-local MCP endpoint.

## Source of truth

- `chezmoi/.chezmoidata/mcp_servers.yaml`: direct MCP entries, Toolkit profile metadata, and which clients receive the gateway.
- `.mcp.json`: project-level gateway plus the direct Hindsight and Draw.io exceptions.
- `scripts/sh/mcp-toolkit.sh` and `scripts/powershell/mcp-toolkit.ps1`: cross-platform profile convergence and secret-store guidance.
- `taskfiles/mcp/taskfile.yml`: public task ordering and preconditions.
- client templates and editor deploy scripts: generated client-specific gateway syntax only.

## Safety and convergence

`task mcp:toolkit:sync` must:

1. Require `docker` and `docker mcp`.
2. Create the `dotfiles` profile if missing.
3. Add the declared catalog entries idempotently.
4. Remove obsolete Toolkit server names, including any stale Hindsight entry from the earlier probe implementation.
5. Print the resulting profile summary without printing secret values.

The explicit secret-sync operation requires `op` and Docker MCP Toolkit, reads each configured
`openclaw` reference with a timeout, and sends the value only through stdin to `docker mcp secret set`.

It must not delete unrelated Docker MCP profiles, change Docker Desktop authentication, or start Hindsight/Hermes. The gateway remains on stdio by default and does not publish a host TCP port.

`task mcp:toolkit:push` runs local convergence first and then pushes only the profile artifact. The registry credential is supplied through Docker's registry login and is never written to the profile. `task mcp:toolkit:pull` retrieves the configured OCI reference; consumers configure Toolkit secrets locally after the pull.

## Acceptance criteria

- The five requested removals are absent from direct data, generated client templates, project MCP configuration, and Toolkit sync commands.
- The eight catalog servers are declared exactly once in the Toolkit profile convergence path, and Hindsight is declared once in the shared direct MCP data.
- All six managed client templates produce the gateway entry.
- Direct `plane`, `drawio`, and `kaggle` entries remain available through the existing common data path.
- Windows and Unix Toolkit sync tasks use the same profile ID and server set.
- The push task converges before publishing and the pull task uses the same configurable OCI reference on both platforms.
- Tests validate profile refs, removed names, gateway emission, Hindsight endpoint, secret-name documentation, and Docker stdio argument shape.
