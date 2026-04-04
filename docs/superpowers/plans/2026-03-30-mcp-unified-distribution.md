# MCP Unified Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `mcp_servers.yaml` to distribute MCP server configs to 9 AI tools via chezmoi templates.

**Architecture:** Add `transport` field to `mcp_servers.yaml`. Each tool's template checks transport type and tool's HTTP support to decide output format. stdio-only tools use `mcp-remote` to bridge HTTP servers. Claude Code uses `run_onchange` script with `claude mcp add`.

**Tech Stack:** chezmoi (Go templates), Pester (tests), PowerShell + Bash (deploy scripts), mcp-remote (npm)

**Spec:** `docs/superpowers/specs/2026-03-30-mcp-unified-distribution-design.md`

**Working directory:** `D:\ruru\dotfiles`

---

## File Structure

### New files

| Path                                                                               | Responsibility                   |
| ---------------------------------------------------------------------------------- | -------------------------------- |
| `chezmoi/AppData/Claude/claude_desktop_config.json.tmpl`                           | Claude Desktop MCP config        |
| `chezmoi/dot_codeium/windsurf/mcp_config.json.tmpl`                                | Windsurf MCP config              |
| `chezmoi/.chezmoiscripts/deploy/llms/run_onchange_deploy_claude_code_mcp.ps1.tmpl` | Claude Code MCP deploy (Windows) |
| `chezmoi/.chezmoiscripts/deploy/llms/run_onchange_deploy_claude_code_mcp.sh.tmpl`  | Claude Code MCP deploy (Unix)    |

### Modified files

| Path                                                         | Change                                                                   |
| ------------------------------------------------------------ | ------------------------------------------------------------------------ |
| `chezmoi/.chezmoidata/mcp_servers.yaml`                      | Add `transport` field, rename `claude` → `claude-code`, add new tool IDs |
| `chezmoi/dot_claude/dot_claude.json.tmpl`                    | `has "claude"` → `has "claude-code"`                                     |
| `chezmoi/dot_codex/config.toml.tmpl`                         | No change (ID `codex` unchanged)                                         |
| `chezmoi/dot_cursor/cli-config.json.tmpl`                    | No change (ID `cursor` unchanged)                                        |
| `chezmoi/dot_gemini/settings.json.tmpl`                      | No change (ID `gemini` unchanged)                                        |
| `chezmoi/editors/vscode/settings.json`                       | Add `mcp` section at end (or convert to .tmpl)                           |
| `chezmoi/editors/zed/settings.json`                          | Add `context_servers` section (or convert to .tmpl)                      |
| `scripts/powershell/tests/chezmoi/ChezmoiTemplate.Tests.ps1` | Add tests for new templates                                              |

---

## Phase 1: Data Model

### Task 1: Add transport field and new tool IDs to mcp_servers.yaml

**Files:**

- Modify: `chezmoi/.chezmoidata/mcp_servers.yaml`
- Modify: `chezmoi/dot_claude/dot_claude.json.tmpl`

- [ ] **Step 1: Update supports IDs**

In `chezmoi/.chezmoidata/mcp_servers.yaml`, change all `- claude` entries to `- claude-code`. Add new tool IDs to servers that should be available everywhere.

For `context7` (currently claude + codex only), keep as-is:

```yaml
- name: context7
  command: pnpm
  args:
    - "dlx"
    - "@upstash/context7-mcp@latest"
  startup_timeout_sec: 30
  supports:
    - codex
    - claude-code
```

For `superlocalmemory`, add all tool IDs and transport:

```yaml
- name: superlocalmemory
  url: "http://localhost:3000/mcp"
  transport: http
  supports:
    - claude-code
    - claude-desktop
    - codex
    - gemini
    - cursor
    - vscode
    - windsurf
    - zed
```

For `qmd`, same pattern:

```yaml
- name: qmd
  url: "http://localhost:3001/mcp"
  transport: http
  supports:
    - claude-code
    - claude-desktop
    - codex
    - gemini
    - cursor
    - vscode
    - windsurf
    - zed
```

For all other servers (linear, serena, github, deepwiki, tavily, exa, firecrawl, drawio, sentry, cloud-run), replace `- claude` with `- claude-code` in their supports list. Optionally add `- claude-desktop`, `- vscode`, `- windsurf`, `- zed` where appropriate (servers using `command` are stdio and work everywhere).

Add `transport: stdio` to all command-based servers (optional but explicit). Add `transport: http` to URL-only servers.

For servers with both `url` and `command` (linear, deepwiki, sentry): no transport field needed — templates use existing logic (url for codex, command for others).

- [ ] **Step 2: Update Claude template**

In `chezmoi/dot_claude/dot_claude.json.tmpl`, change line 6:

```
{{- if has "claude" .supports }}
```

to:

```
{{- if has "claude-code" .supports }}
```

- [ ] **Step 3: Verify templates still work**

Run:

```bash
chezmoi execute-template < chezmoi/dot_claude/dot_claude.json.tmpl 2>&1 | head -5
chezmoi execute-template < chezmoi/dot_codex/config.toml.tmpl 2>&1 | grep -c 'mcp_servers'
chezmoi execute-template < chezmoi/dot_gemini/settings.json.tmpl 2>&1 | head -5
chezmoi execute-template < chezmoi/dot_cursor/cli-config.json.tmpl 2>&1 | head -5
```

Expected: All templates render without error. Claude template still outputs MCP servers.

- [ ] **Step 4: Commit**

```bash
git add chezmoi/.chezmoidata/mcp_servers.yaml chezmoi/dot_claude/dot_claude.json.tmpl
git commit -m "feat: add transport field and new tool IDs to mcp_servers.yaml"
```

---

## Phase 2: New Templates

### Task 2: Claude Desktop template

**Files:**

- Create: `chezmoi/AppData/Claude/claude_desktop_config.json.tmpl`

Note: chezmoi maps `AppData` → `%APPDATA%` on Windows via `create_` prefix or symlink. Check how `chezmoi` handles `%APPDATA%` paths. The target is `%APPDATA%/Claude/claude_desktop_config.json`. In chezmoi source, this maps to a path under the home directory. On Windows, `%APPDATA%` = `C:\Users\<user>\AppData\Roaming`. chezmoi's target is `~` = `C:\Users\<user>`, so the relative path is `AppData/Roaming/Claude/claude_desktop_config.json`.

The chezmoi source path should be: `chezmoi/AppData/Roaming/Claude/claude_desktop_config.json.tmpl`

- [ ] **Step 1: Create the template**

```bash
mkdir -p chezmoi/AppData/Roaming/Claude
```

Create `chezmoi/AppData/Roaming/Claude/claude_desktop_config.json.tmpl`:

```
{
  "mcpServers": {
{{- $first := true }}
{{- if hasKey . "mcp_servers" }}
{{- range .mcp_servers }}
{{- if has "claude-desktop" .supports }}
{{- if not $first }},{{ end }}
{{- $first = false }}
    "{{ .name }}": {
{{- if and (hasKey . "url") (not (hasKey . "command")) }}
      "command": "npx",
      "args": ["-y", "mcp-remote", "{{ .url }}"]
{{- else }}
      "command": "{{ .command }}",
      "args": [{{ range $i, $arg := .args }}{{ if $i }}, {{ end }}"{{ $arg }}"{{ end }}]
{{- end }}
{{- if hasKey . "env" }},
      "env": {
{{- $envFirst := true }}
{{- $hasOp := and (hasKey . "op_env") (lookPath "op") }}
{{- $opEnv := dict }}
{{- if hasKey . "op_env" }}{{ $opEnv = .op_env }}{{ end }}
{{- range $key, $value := .env }}
{{- if not $envFirst }},{{ end }}
{{- $envFirst = false }}
{{- if and $hasOp (hasKey $opEnv $key) }}
        "{{ $key }}": "{{ onepasswordRead (index $opEnv $key) }}"
{{- else }}
        "{{ $key }}": "{{ $value }}"
{{- end }}
{{- end }}
      }
{{- end }}
    }
{{- end }}
{{- end }}
{{- end }}
  }
}
```

Key logic: For servers with `url` only (transport: http), output `mcp-remote` wrapper. For servers with `command`, output directly.

- [ ] **Step 2: Verify template output**

```bash
chezmoi execute-template < chezmoi/AppData/Roaming/Claude/claude_desktop_config.json.tmpl 2>&1
```

Expected: JSON with `mcpServers` containing both stdio servers (command/args) and HTTP servers wrapped with mcp-remote.

- [ ] **Step 3: Commit**

```bash
git add chezmoi/AppData/Roaming/Claude/
git commit -m "feat: add Claude Desktop MCP template with mcp-remote for HTTP servers"
```

---

### Task 3: Windsurf template

**Files:**

- Create: `chezmoi/dot_codeium/windsurf/mcp_config.json.tmpl`

- [ ] **Step 1: Create the template**

```bash
mkdir -p chezmoi/dot_codeium/windsurf
```

Create `chezmoi/dot_codeium/windsurf/mcp_config.json.tmpl`:

```
{
  "mcpServers": {
{{- $first := true }}
{{- if hasKey . "mcp_servers" }}
{{- range .mcp_servers }}
{{- if has "windsurf" .supports }}
{{- if not $first }},{{ end }}
{{- $first = false }}
    "{{ .name }}": {
{{- if and (hasKey . "url") (not (hasKey . "command")) }}
      "serverUrl": "{{ .url }}"
{{- else }}
      "command": "{{ .command }}",
      "args": [{{ range $i, $arg := .args }}{{ if $i }}, {{ end }}"{{ $arg }}"{{ end }}]
{{- end }}
{{- if hasKey . "env" }},
      "env": {
{{- $envFirst := true }}
{{- $hasOp := and (hasKey . "op_env") (lookPath "op") }}
{{- $opEnv := dict }}
{{- if hasKey . "op_env" }}{{ $opEnv = .op_env }}{{ end }}
{{- range $key, $value := .env }}
{{- if not $envFirst }},{{ end }}
{{- $envFirst = false }}
{{- if and $hasOp (hasKey $opEnv $key) }}
        "{{ $key }}": "{{ onepasswordRead (index $opEnv $key) }}"
{{- else }}
        "{{ $key }}": "{{ $value }}"
{{- end }}
{{- end }}
      }
{{- end }}
    }
{{- end }}
{{- end }}
{{- end }}
  }
}
```

Windsurf uses `serverUrl` for HTTP and `command`/`args` for stdio.

- [ ] **Step 2: Verify**

```bash
chezmoi execute-template < chezmoi/dot_codeium/windsurf/mcp_config.json.tmpl 2>&1
```

- [ ] **Step 3: Commit**

```bash
git add chezmoi/dot_codeium/
git commit -m "feat: add Windsurf MCP template"
```

---

### Task 4: VS Code mcp.json template

**Files:**

- Create: `chezmoi/editors/vscode/dot_vscode/mcp.json.tmpl`

VS Code reads MCP config from `.vscode/mcp.json` in workspace or from user settings. For global user config, add to `settings.json`. However, since `settings.json` is already a static file (not a template), create a separate deploy script or use the `mcp` key approach.

The simplest approach: create a standalone `mcp.json.tmpl` that gets deployed to the VS Code user config directory.

- [ ] **Step 1: Determine VS Code user config path**

On Windows: `%APPDATA%/Code/User/settings.json` (or `mcp.json` in user profile).

Actually, VS Code MCP is configured either per-workspace (`.vscode/mcp.json`) or in user `settings.json` under `"mcp"` key. For global config, we should add to user `settings.json`.

Since VS Code `settings.json` is a large static file, the best approach is a deploy script that merges the `mcp` section using a tool like `jq` or Python.

Create `chezmoi/.chezmoiscripts/deploy/editors/run_onchange_deploy_vscode_mcp.ps1.tmpl`:

```powershell
# {{ template hash of mcp_servers.yaml to trigger on change }}
# chezmoi:template: hash={{ include ".chezmoidata/mcp_servers.yaml" | sha256sum }}

$settingsPath = Join-Path $env:APPDATA "Code\User\settings.json"
if (-not (Test-Path $settingsPath)) {
    Write-Host "[vscode-mcp] settings.json not found, skipping"
    exit 0
}

$settings = Get-Content $settingsPath -Raw | ConvertFrom-Json

# Build MCP servers object
$mcpServers = @{}
{{ range .mcp_servers }}
{{- if has "vscode" .supports }}
{{- if and (hasKey . "url") (not (hasKey . "command")) }}
$mcpServers["{{ .name }}"] = @{
    type = "http"
    url = "{{ .url }}"
}
{{- else }}
$mcpServers["{{ .name }}"] = @{
    type = "stdio"
    command = "{{ .command }}"
    args = @({{ range .args }}"{{ . }}", {{ end }})
}
{{- end }}
{{- end }}
{{ end }}

# Merge into settings
if (-not (Get-Member -InputObject $settings -Name "mcp" -MemberType NoteProperty)) {
    $settings | Add-Member -NotePropertyName "mcp" -NotePropertyValue @{}
}
$settings.mcp.servers = $mcpServers
$settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8

Write-Host "[vscode-mcp] Updated $settingsPath with $($mcpServers.Count) MCP servers"
```

- [ ] **Step 2: Commit**

```bash
git add chezmoi/.chezmoiscripts/deploy/editors/
git commit -m "feat: add VS Code MCP deploy script"
```

---

### Task 5: Zed context_servers in settings.json

**Files:**

- Modify: `chezmoi/editors/zed/settings.json` → convert to `.tmpl` or use deploy script

Zed uses JSONC (comments allowed) in `settings.json`. Converting to a chezmoi template would lose comments. Better approach: deploy script that merges `context_servers` into existing Zed settings.

- [ ] **Step 1: Create deploy script**

Create `chezmoi/.chezmoiscripts/deploy/editors/run_onchange_deploy_zed_mcp.ps1.tmpl`:

```powershell
# {{ template hash }}
# chezmoi:template: hash={{ include ".chezmoidata/mcp_servers.yaml" | sha256sum }}

$settingsPath = Join-Path $env:APPDATA "Zed\settings.json"
if (-not (Test-Path $settingsPath)) {
    Write-Host "[zed-mcp] settings.json not found, skipping"
    exit 0
}

# Zed uses JSONC - read, strip comments, modify, write back
$content = Get-Content $settingsPath -Raw

# Use Python to handle JSONC parsing and merging
python3 -c @"
import json, re, sys

content = open(sys.argv[1], 'r').read()
# Strip // comments (simple approach - doesn't handle strings with //)
stripped = re.sub(r'//.*$', '', content, flags=re.MULTILINE)
# Strip trailing commas before } or ]
stripped = re.sub(r',\s*([}\]])', r'\1', stripped)

try:
    settings = json.loads(stripped)
except json.JSONDecodeError:
    print('[zed-mcp] Failed to parse settings.json, skipping')
    sys.exit(0)

servers = {}
{{ range .mcp_servers }}
{{- if has "zed" .supports }}
{{- if and (hasKey . "url") (not (hasKey . "command")) }}
servers['{{ .name }}'] = {
    'source': 'custom',
    'command': 'npx',
    'args': ['-y', 'mcp-remote', '{{ .url }}']
}
{{- else }}
servers['{{ .name }}'] = {
    'source': 'custom',
    'command': '{{ .command }}',
    'args': [{{ range $i, $arg := .args }}{{ if $i }}, {{ end }}'{{ $arg }}'{{ end }}]
}
{{- end }}
{{- end }}
{{ end }}

settings['context_servers'] = servers
# Write back (without comments - they'll be lost)
with open(sys.argv[1], 'w') as f:
    json.dump(settings, f, indent=2)

print(f'[zed-mcp] Updated {sys.argv[1]} with {len(servers)} context servers')
"@ "$settingsPath"
```

Note: This approach loses JSONC comments. If preserving comments is important, use a JSONC-aware tool or maintain a separate section marker.

- [ ] **Step 2: Commit**

```bash
git add chezmoi/.chezmoiscripts/deploy/editors/
git commit -m "feat: add Zed MCP deploy script"
```

---

## Phase 3: Claude Code Deploy Script

### Task 6: Claude Code run_onchange script

**Files:**

- Create: `chezmoi/.chezmoiscripts/deploy/llms/run_onchange_deploy_claude_code_mcp.ps1.tmpl`
- Create: `chezmoi/.chezmoiscripts/deploy/llms/run_onchange_deploy_claude_code_mcp.sh.tmpl`

- [ ] **Step 1: Create Windows script**

```powershell
# chezmoi:template: hash={{ include ".chezmoidata/mcp_servers.yaml" | sha256sum }}

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Host "[claude-code-mcp] claude CLI not found, skipping"
    exit 0
}

Write-Host "[claude-code-mcp] Syncing MCP servers..."

# Get current servers
$currentJson = claude mcp list --json 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
$currentNames = @()
if ($currentJson) { $currentNames = $currentJson | ForEach-Object { $_.name } }

{{ range .mcp_servers }}
{{- if has "claude-code" .supports }}
{{- if and (hasKey . "url") (not (hasKey . "command")) }}
# {{ .name }} (HTTP)
if ($currentNames -notcontains "{{ .name }}") {
    claude mcp add --transport http "{{ .name }}" "{{ .url }}" -s user 2>$null
    Write-Host "[claude-code-mcp] Added {{ .name }} (http)"
} else {
    Write-Host "[claude-code-mcp] {{ .name }} already exists"
}
{{- else }}
# {{ .name }} (stdio)
if ($currentNames -notcontains "{{ .name }}") {
    claude mcp add "{{ .name }}" -s user -- {{ .command }} {{ range .args }}"{{ . }}" {{ end }}2>$null
    Write-Host "[claude-code-mcp] Added {{ .name }} (stdio)"
} else {
    Write-Host "[claude-code-mcp] {{ .name }} already exists"
}
{{- end }}
{{- end }}
{{ end }}

Write-Host "[claude-code-mcp] Done"
```

- [ ] **Step 2: Create Unix script**

```bash
#!/bin/bash
# chezmoi:template: hash={{ include ".chezmoidata/mcp_servers.yaml" | sha256sum }}

if ! command -v claude >/dev/null 2>&1; then
  echo "[claude-code-mcp] claude CLI not found, skipping"
  exit 0
fi

echo "[claude-code-mcp] Syncing MCP servers..."

{{ range .mcp_servers }}
{{- if has "claude-code" .supports }}
{{- if and (hasKey . "url") (not (hasKey . "command")) }}
claude mcp add --transport http "{{ .name }}" "{{ .url }}" -s user 2>/dev/null || true
{{- else }}
claude mcp add "{{ .name }}" -s user -- {{ .command }} {{ range .args }}"{{ . }}" {{ end }}2>/dev/null || true
{{- end }}
{{- end }}
{{ end }}

echo "[claude-code-mcp] Done"
```

- [ ] **Step 3: Commit**

```bash
git add chezmoi/.chezmoiscripts/deploy/llms/run_onchange_deploy_claude_code_mcp.*
git commit -m "feat: add Claude Code MCP deploy scripts (run_onchange)"
```

---

## Phase 4: Tests

### Task 7: Update and add tests

**Files:**

- Modify: `scripts/powershell/tests/chezmoi/ChezmoiTemplate.Tests.ps1`

- [ ] **Step 1: Update existing test for claude-code ID change**

In the existing test that validates `onepasswordRead` guards, the test scans all `.tmpl` files — no change needed since it's file-based.

- [ ] **Step 2: Add test for transport/mcp-remote generation**

Add a new Context block:

```powershell
Context 'HTTP MCP サーバーが stdio-only ツールで mcp-remote ラッパーを生成すること' {
    BeforeAll {
        $script:claudeDesktopTemplate = Join-Path $script:chezmoiRoot "AppData/Roaming/Claude/claude_desktop_config.json.tmpl"
    }

    It 'Claude Desktop テンプレートで HTTP サーバーに mcp-remote が使われていること' {
        if (-not (Test-Path $script:claudeDesktopTemplate)) {
            Set-ItResult -Skipped -Because "Claude Desktop テンプレートが存在しない"
            return
        }
        $content = Get-Content -Path $script:claudeDesktopTemplate -Raw
        $content | Should -Match 'mcp-remote' -Because "HTTP MCP サーバーは mcp-remote 経由で接続する"
    }
}

Context 'supports ID の整合性' {
    It 'mcp_servers.yaml で claude-code が使われ、旧 claude ID が残っていないこと' {
        $content = Get-Content -Path $script:mcpServersPath -Raw
        $content | Should -Not -Match '^\s+- claude$' -Because "旧 claude ID は claude-code に移行済み"
    }
}
```

- [ ] **Step 3: Run tests**

```bash
cd scripts/powershell/tests && pwsh -NoProfile -Command "& { ./Invoke-Tests.ps1 -Path ./chezmoi/ChezmoiTemplate.Tests.ps1 -MinimumCoverage 0 }"
```

Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add scripts/powershell/tests/chezmoi/ChezmoiTemplate.Tests.ps1
git commit -m "test: add MCP transport and supports ID validation tests"
```

---

## Phase 5: ChatGPT Desktop (Investigation + Implementation)

### Task 8: Investigate ChatGPT Desktop MCP config

**Files:** None (research task)

- [ ] **Step 1: Check if ChatGPT Desktop is installed**

```bash
ls "$LOCALAPPDATA/Programs/ChatGPT/" 2>/dev/null || ls "$LOCALAPPDATA/Packages/" 2>/dev/null | grep -i openai
```

- [ ] **Step 2: Search for config files**

```bash
find "$APPDATA" "$LOCALAPPDATA" -name "*chatgpt*" -o -name "*openai*" 2>/dev/null | head -20
```

- [ ] **Step 3: Check ChatGPT Desktop MCP documentation**

Search for the exact config file path and format. If ChatGPT Desktop uses a config file similar to Claude Desktop, create a template. If it requires UI-only setup, document this limitation and skip template creation.

- [ ] **Step 4: Create template or document limitation**

If config file exists: create template following Claude Desktop pattern.
If UI-only: add a note to the spec and skip.

- [ ] **Step 5: Commit findings**

```bash
git add -A
git commit -m "feat: add ChatGPT Desktop MCP template (or docs: document ChatGPT limitation)"
```

---

## Phase 6: Apply and Verify

### Task 9: Full apply and verification

**Files:** None (operational verification)

- [ ] **Step 1: Run chezmoi apply**

```bash
chezmoi apply --force
```

- [ ] **Step 2: Verify Claude Code MCP servers**

```bash
claude mcp list 2>&1
```

Expected: superlocalmemory and qmd listed.

- [ ] **Step 3: Verify Claude Desktop config**

```bash
cat "$APPDATA/Claude/claude_desktop_config.json" 2>&1
```

Expected: JSON with mcpServers including mcp-remote wrappers for HTTP servers.

- [ ] **Step 4: Verify Windsurf config**

```bash
cat ~/.codeium/windsurf/mcp_config.json 2>&1
```

Expected: JSON with mcpServers using serverUrl for HTTP.

- [ ] **Step 5: Verify Codex/Gemini/Cursor configs**

```bash
grep -A2 'superlocalmemory\|qmd' ~/.codex/config.toml ~/.gemini/settings.json ~/.cursor/cli-config.json
```

Expected: URL-based entries for both servers.

- [ ] **Step 6: Final commit**

```bash
git add -A
git commit -m "feat: complete MCP unified distribution — verified all 9 tools"
```
