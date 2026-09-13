# Docker MCP Toolkit shared profile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move Docker MCP Toolkit-compatible servers into the shared `dotfiles` profile and connect every managed agent to its gateway while retaining unsupported MCPs through the existing SSOT.

**Architecture:** `.chezmoidata/mcp_servers.yaml` will distinguish the Toolkit profile from direct servers. Cross-platform scripts will converge the Toolkit profile, while all client templates will emit one stdio gateway entry plus direct exceptions. Hindsight remains direct because Docker MCP Gateway rejects local HTTP remotes. Toolkit secrets stay in Docker Desktop's secret store.

**Tech Stack:** Docker MCP Toolkit CLI, Docker MCP Catalog, chezmoi Go templates, Go Task, Bash, PowerShell, Pester/static repository tests.

**Spec:** `docs/superpowers/specs/2026-09-13-docker-mcp-toolkit-design.md`

## Global Constraints

- The Toolkit profile ID is `dotfiles`.
- Toolkit servers are `context7`, `deepwiki`, `exa`, `firecrawl`, `github-official`, `obsidian`, `playwright`, and `tavily`.
- Hindsight uses `http://127.0.0.1:8888/mcp/codex-shared/`, is emitted directly for every client, and is not started by the Toolkit task.
- `linear`, `sentry`, `cloud-run`, `superlocalmemory`, and `qmd` must be removed.
- `plane`, `drawio`, and `kaggle` remain direct MCP entries.
- Secret values must not be committed or emitted into generated client files.
- Existing unrelated `flake.lock` changes in the main worktree must remain untouched.

---

### Task 1: Add failing contract tests for the Toolkit migration

**Files:**

- Create: `scripts/powershell/tests/chezmoi/DockerMcpToolkit.Tests.ps1`
- Test: `scripts/powershell/tests/chezmoi/DockerMcpToolkit.Tests.ps1`

- [ ] **Step 1: Write tests for the Toolkit profile and removals**

Add Pester contexts that assert the data file contains the exact Toolkit refs and profile ID, excludes the five removed names, retains `plane`, `drawio`, and `kaggle`, and contains the Hindsight endpoint.

- [ ] **Step 2: Write tests for gateway emission**

Assert that Codex, Cursor, Gemini, and Windsurf templates contain the `docker mcp gateway run --profile dotfiles` shape, and that the VS Code/Zed deploy templates add `MCP_DOCKER`.

- [ ] **Step 3: Write tests for cross-platform sync contracts**

Assert the Bash and PowerShell sync adapters use the same profile ID, all eight catalog refs, the Hindsight entry, and remove obsolete names. Assert the adapters do not contain secret values.

- [ ] **Step 4: Run the focused tests and verify RED**

Run:

```bash
pwsh -NoProfile -Command "& ./scripts/powershell/tests/Invoke-Tests.ps1 -Path ./scripts/powershell/tests/chezmoi/ChezmoiTemplate.Tests.ps1 -MinimumCoverage 0"
```

Expected: the new assertions fail because the Toolkit profile and gateway entries do not yet exist.

### Task 2: Refactor the MCP data model and project configuration

**Files:**

- Modify: `chezmoi/.chezmoidata/mcp_servers.yaml`
- Modify: `.mcp.json`
- Modify: `docs/chezmoi/secrets.md`

- [ ] **Step 1: Add the Toolkit metadata and remove migrated direct entries**

Add profile `dotfiles`, the gateway client IDs, and the eight catalog refs. Remove the migrated catalog server blocks and the five requested removals from `mcp_servers`. Keep `hindsight`, `plane`, `drawio`, and `kaggle` in the direct list; Hindsight is direct because the Toolkit rejects local HTTP remotes.

- [ ] **Step 2: Define the direct Hindsight exception**

Keep `hindsight` in the direct MCP list with URL `http://127.0.0.1:8888/mcp/codex-shared/` and all six client support IDs. Do not add an API key or secret value. Docker MCP Gateway rejects this local HTTP endpoint.

- [ ] **Step 3: Replace project-level duplicated catalog entries**

Change `.mcp.json` to expose `MCP_DOCKER` through the `dotfiles` profile and retain only direct `drawio` if the project still needs it.

- [ ] **Step 4: Document Toolkit secret setup**

Document the Docker Desktop secret-store names and the `task mcp:toolkit:sync` prerequisite without exposing any secret or 1Password value.

### Task 3: Implement cross-platform Toolkit profile convergence

**Files:**

- Create: `scripts/sh/mcp-toolkit.sh`
- Create: `scripts/powershell/mcp-toolkit.ps1`
- Create: `taskfiles/mcp/taskfile.yml`
- Modify: `Taskfile.yml`

- [ ] **Step 1: Implement Unix sync behavior**

Add `sync` and `status` actions. The sync action must ensure the profile exists, add all declared catalog refs, remove obsolete names including any stale Hindsight entry, and show the profile. Log only names and statuses.

- [ ] **Step 2: Implement Windows sync behavior**

Implement the same operations with PowerShell path handling and `Join-Path`, using `docker mcp` commands and the same profile/server list. Keep secret values out of command output.

- [ ] **Step 3: Add public Taskfile commands**

Include `taskfiles/mcp/taskfile.yml` from the root Taskfile. Add public `mcp:toolkit:sync` and `mcp:toolkit:status` tasks with Docker preconditions and Unix/Windows adapters.

- [ ] **Step 4: Run adapter syntax tests**

Run `bash -n scripts/sh/mcp-toolkit.sh`, PowerShell parser validation, and the Taskfile dry-run commands. Verify the new tests still fail only on gateway/template assertions.

### Task 4: Generate the shared gateway connection in every client

**Files:**

- Modify: `chezmoi/dot_codex/config.toml.tmpl`
- Modify: `chezmoi/dot_cursor/cli-config.json.tmpl`
- Modify: `chezmoi/dot_gemini/settings.json.tmpl`
- Modify: `chezmoi/dot_codeium/windsurf/mcp_config.json.tmpl`
- Modify: `chezmoi/.chezmoiscripts/deploy/editors/run_onchange_deploy_vscode_mcp.ps1.tmpl`
- Modify: `chezmoi/.chezmoiscripts/deploy/editors/run_onchange_deploy_zed_mcp.ps1.tmpl`
- Create: `chezmoi/.chezmoiscripts/deploy/editors/run_onchange_deploy_vscode_mcp.sh.tmpl`
- Create: `chezmoi/.chezmoiscripts/deploy/editors/run_onchange_deploy_zed_mcp.sh.tmpl`
- Modify: `scripts/powershell/tests/chezmoi/ChezmoiTemplate.Tests.ps1`

- [ ] **Step 1: Add the Codex gateway block**

Emit `MCP_DOCKER` as a Docker stdio server with the existing Windows readiness wrapper branch and `startup_timeout_sec`.

- [ ] **Step 2: Add the Cursor, Gemini, and Windsurf gateway blocks**

Emit the same command/args in each JSON format, preserving valid comma handling and leaving direct unsupported servers intact.

- [ ] **Step 3: Add VS Code and Zed gateway entries**

Build `MCP_DOCKER` with `type=stdio` for VS Code and `source=custom`, `command=docker`, and profile args for Zed before processing direct servers. Add matching Unix scripts that write the same entries to the native Code/Zed configuration paths.

- [ ] **Step 4: Render and parse generated configuration**

Run the existing chezmoi template checks and parse rendered JSON/TOML. Verify each client has exactly one `MCP_DOCKER` entry and no migrated server duplicate.

### Task 5: Verify and document the complete migration

**Files:**

- Modify: `docs/superpowers/specs/2026-09-13-docker-mcp-toolkit-design.md`
- Modify: `docs/chezmoi/secrets.md`
- Modify: `docs/architecture.md` if the MCP ownership table needs a link

- [ ] **Step 1: Run focused tests**

Run the Pester chezmoi tests, shell syntax checks, Taskfile dry runs, and `docker mcp gateway run --profile dotfiles --dry-run` after syncing the local profile where Docker is available. Confirm the eight Toolkit servers initialize; Hindsight remains outside this dry run by design.

- [ ] **Step 2: Run repository quality checks**

Run `nix fmt -- --fail-on-change` independently of flake checks, then the repository-authoritative tests relevant to changed files.

- [ ] **Step 3: Review the diff against Issue #612**

Confirm no user `flake.lock` change was copied into the feature worktree, no secret value is present, removed names are absent, and Hermes internal MCP boundaries remain unchanged.

- [ ] **Step 4: Commit with the repository task**

Use the repository convention:

```bash
task commit -- "feat: centralize MCP servers with Docker Toolkit"
```
