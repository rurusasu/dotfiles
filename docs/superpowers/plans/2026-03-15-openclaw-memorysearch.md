# OpenClaw memorySearch + Secrets 統一 Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable OpenClaw's builtin memorySearch with Gemini embedding for session log and memory file vector search, and unify all secrets via Docker secrets.

**Architecture:** Add `memorySearch` config to OpenClaw's `agents.defaults`, inject `GEMINI_API_KEY` via Docker secret (1Password → file → entrypoint export), remove unused env vars (`OPENAI_API_KEY`, `GEMINI_API_KEY`) from docker-compose.yml.

**Tech Stack:** OpenClaw (Bun/Node), Docker Compose, chezmoi templates, PowerShell (Handler), 1Password CLI (`op`)

**Spec:** `docs/superpowers/specs/2026-03-15-openclaw-memorysearch-design.md`

---

## Chunk 1: Config and Docker Changes

### Task 1: Add memorySearch to OpenClaw config template

**Files:**
- Modify: `chezmoi/dot_openclaw/openclaw.docker.json.tmpl:32` (after `compaction` block)

- [ ] **Step 1: Add memorySearch section after compaction block**

In `chezmoi/dot_openclaw/openclaw.docker.json.tmpl`, add the following after the closing `}` of `"compaction"` (line 32) and before `"contextPruning"`:

```json
      "memorySearch": {
        "enabled": true,
        "provider": "gemini",
        "model": "gemini-embedding-2-preview",
        "sources": ["memory", "sessions"],
        "experimental": {
          "sessionMemory": true
        },
        "query": {
          "hybrid": {
            "enabled": true
          }
        }
      },
```

- [ ] **Step 2: Validate template syntax**

Run: `chezmoi execute-template < chezmoi/dot_openclaw/openclaw.docker.json.tmpl > /dev/null 2>&1 && echo OK || echo FAIL`
Expected: OK (template renders without errors). JSON validation is deferred to Task 5 (chezmoi apply + container recreate).

- [ ] **Step 3: Commit**

```bash
git add chezmoi/dot_openclaw/openclaw.docker.json.tmpl
git commit -m "feat(openclaw): add memorySearch config with Gemini embedding"
```

### Task 2: Unify secrets in docker-compose.yml

**Files:**
- Modify: `docker/openclaw/docker-compose.yml:43-53` (environment section), `docker/openclaw/docker-compose.yml:88-90` (secrets section), `docker/openclaw/docker-compose.yml:106-110` (top-level secrets)

- [ ] **Step 1: Remove OPENAI_API_KEY and GEMINI_API_KEY env vars**

In `docker/openclaw/docker-compose.yml`, remove these lines from the `environment:` section:

```yaml
      # Optional: set OPENAI_API_KEY in .env for embeddings (not required for Codex OAuth)
      OPENAI_API_KEY: ${OPENAI_API_KEY:-}
```

and:

```yaml
      # Gemini CLI authentication for ACP agent sessions (sessions_spawn agentId="gemini")
      GEMINI_API_KEY: ${GEMINI_API_KEY:-}
```

- [ ] **Step 2: Add gemini_api_key to service secrets list**

In the `services.openclaw.secrets:` section (around line 88), add:

```yaml
    secrets:
      - github_token
      - xai_api_key
      - gemini_api_key
```

- [ ] **Step 3: Add gemini_api_key to top-level secrets definition**

In the top-level `secrets:` section (around line 106), add:

```yaml
  gemini_api_key:
    file: ${OPENCLAW_GEMINI_API_KEY_FILE:?Set OPENCLAW_GEMINI_API_KEY_FILE in .env}
```

- [ ] **Step 4: Validate compose syntax**

Run: `cd D:/dotfiles/docker/openclaw && docker compose config --quiet 2>&1 && echo OK || echo FAIL`
Expected: OK (or expected error about unset .env vars if not yet configured — that's fine at this stage)

- [ ] **Step 5: Commit**

```bash
git add docker/openclaw/docker-compose.yml
git commit -m "feat(openclaw): unify secrets via Docker secrets, add gemini_api_key"
```

### Task 3: Add GEMINI_API_KEY secret reading to entrypoint.sh

**Files:**
- Modify: `docker/openclaw/entrypoint.sh:30-35` (after xAI block, before log output)

- [ ] **Step 1: Add Gemini secret reading block after xAI block (after line 30)**

Insert after the xAI API key block (after `fi` on line 30) and before the log output (line 31):

```sh
# --- Gemini API key (embedding): read from Docker secret ---
_gemini_secret_file="/run/secrets/gemini_api_key"
if [ -f "$_gemini_secret_file" ]; then
  _gemini_key="$(cat "$_gemini_secret_file")"
  if [ -n "$_gemini_key" ]; then
    GEMINI_API_KEY="$_gemini_key"
    export GEMINI_API_KEY
  fi
fi
```

- [ ] **Step 2: Add _gemini_status variable and extend log line**

Add after the existing `_xai_status` initialization (the line containing `_xai_status="not set"`):

```sh
_gemini_status="not set"
if [ -n "${GEMINI_API_KEY:-}" ]; then _gemini_status="ok ($(printf "%s" "$GEMINI_API_KEY" | wc -c) chars)"; fi
```

Update the existing log line (the `echo "[entrypoint] secrets:` line) to include GEMINI_API_KEY:

```sh
echo "[entrypoint] secrets: GITHUB_TOKEN=${_gh_len} chars, XAI_API_KEY=${_xai_status}, GEMINI_API_KEY=${_gemini_status}"
```

- [ ] **Step 3: Validate shell syntax**

Run: `bash -n docker/openclaw/entrypoint.sh && echo OK || echo FAIL`
Expected: OK

- [ ] **Step 4: Commit**

```bash
git add docker/openclaw/entrypoint.sh
git commit -m "feat(openclaw): read GEMINI_API_KEY from Docker secret for embedding"
```

## Chunk 2: Handler and Verification

### Task 4: Update Handler.OpenClaw.ps1

**Files:**
- Modify: `scripts/powershell/handlers/Handler.OpenClaw.ps1:135-139` (WriteSecretFile calls)
- Modify: `scripts/powershell/handlers/Handler.OpenClaw.ps1:293-304` (EnsureEnvFile content)
- Test: `scripts/powershell/tests/handlers/Handler.OpenClaw.Tests.ps1`

- [ ] **Step 1: Add WriteSecretFile call for gemini_api_key**

In `scripts/powershell/handlers/Handler.OpenClaw.ps1`, add after the `xai_api_key` WriteSecretFile call (after line 139):

```powershell
            $this.WriteSecretFile(
                "op://Personal/OpenClawGeminiAPI/credential",
                "gemini_api_key",
                $false
            )
```

- [ ] **Step 2: Add OPENCLAW_GEMINI_API_KEY_FILE to EnsureEnvFile**

In the `$envContent` here-string (line 293-304), add after the `OPENCLAW_XAI_API_KEY_FILE` line:

```
OPENCLAW_GEMINI_API_KEY_FILE=$secretDir/gemini_api_key
```

- [ ] **Step 3: Update test — add OPENCLAW_GEMINI_API_KEY env var to BeforeEach/AfterEach blocks**

In `scripts/powershell/tests/handlers/Handler.OpenClaw.Tests.ps1`, for each `BeforeEach` block that sets `$env:OPENCLAW_XAI_API_KEY`, also set:

```powershell
$env:OPENCLAW_GEMINI_API_KEY = ""
```

And in each `AfterEach` block, add:

```powershell
Remove-Item -Path Env:\OPENCLAW_GEMINI_API_KEY -ErrorAction SilentlyContinue
```

- [ ] **Step 4: Add test for OPENCLAW_GEMINI_API_KEY_FILE in .env content**

In the `'Apply - .env content'` context, add a new test:

```powershell
        It 'should include OPENCLAW_GEMINI_API_KEY_FILE in .env' {
            $script:envContent = ""
            Mock Write-Host { }
            Mock Start-SleepSafe { }
            Mock Test-PathExist {
                param($Path)
                if ($Path -match "\.env$") { return $false }
                return $true
            }
            Mock Set-ContentNoNewline {
                param($Path, $Value)
                if ($Path -match "\.env$") {
                    $script:envContent = $Value
                }
            }
            Mock Invoke-Docker {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "up") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "ps") { return "openclaw" }
                return ""
            }

            $handler.Apply($ctx)

            $script:envContent | Should -Match "OPENCLAW_GEMINI_API_KEY_FILE=.+/gemini_api_key"
        }
```

- [ ] **Step 5: Run tests**

Run: `pwsh -Command "Invoke-Pester scripts/powershell/tests/handlers/Handler.OpenClaw.Tests.ps1 -Output Detailed"`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add scripts/powershell/handlers/Handler.OpenClaw.ps1 scripts/powershell/tests/handlers/Handler.OpenClaw.Tests.ps1
git commit -m "feat(openclaw): add gemini_api_key to Handler secrets and .env generation"
```

### Task 5: Create .env.example

**Files:**
- Create: `docker/openclaw/.env.example`

- [ ] **Step 1: Create .env.example file**

Create `docker/openclaw/.env.example` with all expected variables (reference for manual setup):

```
OPENCLAW_PORT=18789
OPENCLAW_UID=1000
OPENCLAW_GID=1000
OPENCLAW_CONFIG_FILE=/path/to/.openclaw/openclaw.docker.json
TZ=Asia/Tokyo
GEMINI_CREDENTIALS_DIR=/path/to/.gemini
CLAUDE_CREDENTIALS_DIR=/path/to/.claude
CLAUDE_CONFIG_JSON=/path/to/.claude.json
OPENCLAW_GITHUB_TOKEN_FILE=/path/to/.openclaw/secrets/github_token
OPENCLAW_XAI_API_KEY_FILE=/path/to/.openclaw/secrets/xai_api_key
OPENCLAW_GEMINI_API_KEY_FILE=/path/to/.openclaw/secrets/gemini_api_key
```

- [ ] **Step 2: Commit**

```bash
git add docker/openclaw/.env.example
git commit -m "docs(openclaw): add .env.example for manual setup reference"
```

### Task 6: Write secrets file, deploy, and verify

**Files:**
- No code changes — operational steps

- [ ] **Step 1: Write Gemini API key secret file from 1Password**

Run: `op read "op://Personal/OpenClawGeminiAPI/credential" > ~/.openclaw/secrets/gemini_api_key`

Verify: `cat ~/.openclaw/secrets/gemini_api_key | head -c 10` — should show `AIzaSy...`

- [ ] **Step 2: Add OPENCLAW_GEMINI_API_KEY_FILE to existing .env**

Add to `docker/openclaw/.env`:

```
OPENCLAW_GEMINI_API_KEY_FILE=<path-to-home>/.openclaw/secrets/gemini_api_key
```

(Use forward slashes, same format as existing `OPENCLAW_GITHUB_TOKEN_FILE` line)

- [ ] **Step 3: Apply chezmoi to render updated config template**

Run: `chezmoi apply`

Verify: `grep memorySearch ~/.openclaw/openclaw.docker.json` — should show the memorySearch section

- [ ] **Step 4: Recreate container with new secrets**

Run: `cd docker/openclaw && docker compose up -d --build`

Wait for container to start, then verify secrets injection:

Run: `docker logs openclaw 2>&1 | grep "secrets:"`
Expected: `[entrypoint] secrets: GITHUB_TOKEN=... chars, XAI_API_KEY=ok (...), GEMINI_API_KEY=ok (... chars)`

- [ ] **Step 5: Verify memorySearch status**

Run: `docker exec openclaw sh -c 'openclaw memory status --deep --json 2>&1'`

Expected output should show:
- `"provider": "gemini"` (not `"none"`)
- `"searchMode"` should not be `"fts-only"`
- `"embeddingProbe": { "ok": true }` (Gemini API reachable)
- `"sources"` should include `"memory"` and `"sessions"` (if sessionMemory took effect)

- [ ] **Step 6: Test memory search**

Run: `docker exec openclaw sh -c 'openclaw memory search "superpowers skills" 2>&1'`

Expected: Returns results from existing memory files (if indexed) or triggers initial indexing.

- [ ] **Step 7: Commit spec and plan**

```bash
git add docs/superpowers/specs/2026-03-15-openclaw-memorysearch-design.md docs/superpowers/plans/2026-03-15-openclaw-memorysearch.md
git commit -m "docs(openclaw): add memorySearch design spec and implementation plan"
```
