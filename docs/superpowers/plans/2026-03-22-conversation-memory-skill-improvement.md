# 会話記憶 & スキル自己改善ループ Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a 3-layer conversation memory system (Hot/Warm/Cold) and automate Cognee's dormant skill self-improvement loop via PostToolUse hooks, explicit `/feedback` command, and daily cron batch.

**Architecture:** Sessions JSONL (7-day TTL) → daily cron reads files → `ingest_transcript` adds to Cognee → `batch_cognify` builds knowledge graph → `search_knowledge` + `get_skill_status` detect problem skills → auto-amend. PostToolUse hook logs every skill execution immediately. Cognee MCP container reads OpenClaw sessions via shared `openclaw-home` volume (ro).

**Tech Stack:** Python 3.12 (Cognee MCP tools), Node.js (PostToolUse hook), chezmoi Go templates (OpenClaw config), Docker Compose, SQLite3, Cognee SDK (`cognee.add`/`cognee.cognify`/`cognee.search`)

**Spec:** `docs/superpowers/specs/2026-03-22-conversation-memory-and-skill-self-improvement-design.md`

---

## File Structure

| File                                                     | Responsibility                                                                                 |
| -------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `docker/cognee-skills/skills_tools/ingest_state.py`      | NEW: SQLite state management for session ingestion tracking                                    |
| `docker/cognee-skills/skills_tools/ingest_transcript.py` | NEW: Read JSONL file, add to Cognee dataset                                                    |
| `docker/cognee-skills/skills_tools/batch_cognify.py`     | NEW: Run `cognee.cognify()` across all pending datasets                                        |
| `docker/cognee-skills/skills_tools/search_knowledge.py`  | NEW: Search Cognee knowledge graph for conversation-extracted knowledge                        |
| `docker/cognee-skills/skills_tools/__init__.py`          | MODIFY: Register 3 new tools                                                                   |
| `docker/cognee-skills/docker-compose.yml`                | MODIFY: Add `openclaw-home` volume mount (ro)                                                  |
| `docker/openclaw/hooks/log-skill-execution.js`           | NEW: PostToolUse hook script for skill execution logging                                       |
| `docker/openclaw/Dockerfile`                             | MODIFY: COPY hooks/ into image                                                                 |
| `docker/openclaw/entrypoint.sh`                          | MODIFY: Inject Cognee feedback rules into AGENTS.md + wire PostToolUse hook into settings.json |
| `chezmoi/.chezmoidata/openclaw.yaml`                     | MODIFY: Add `slackThreadInitialHistoryLimit`                                                   |
| `chezmoi/dot_openclaw/openclaw.docker.json.tmpl`         | MODIFY: Add `thread.initialHistoryLimit`                                                       |
| `chezmoi/dot_openclaw/cron/jobs.seed.json.tmpl`          | MODIFY: Add `cognee-daily-ingest` cron job                                                     |
| `docs/chezmoi/dot_openclaw/07-channels.md`               | MODIFY: Document `initialHistoryLimit`                                                         |

---

## Task 1: SQLite Ingest State Manager

**Files:**

- Create: `docker/cognee-skills/skills_tools/ingest_state.py`

- [ ] **Step 1: Create ingest_state.py**

```python
"""SQLite-based state management for session ingestion deduplication."""

import sqlite3
from datetime import datetime, timezone
from pathlib import Path

DB_PATH = Path("/app/data/cognee-ingest-state.db")


def _connect() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(DB_PATH))
    conn.execute(
        """CREATE TABLE IF NOT EXISTS ingested_sessions (
            session_id TEXT PRIMARY KEY,
            agent_id TEXT NOT NULL,
            ingested_at TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            retry_count INTEGER NOT NULL DEFAULT 0
        )"""
    )
    conn.commit()
    return conn


def is_ingested(session_id: str) -> bool:
    conn = _connect()
    try:
        row = conn.execute(
            "SELECT status FROM ingested_sessions WHERE session_id = ?",
            (session_id,),
        ).fetchone()
        return row is not None and row[0] == "ingested"
    finally:
        conn.close()


def should_retry(session_id: str) -> bool:
    conn = _connect()
    try:
        row = conn.execute(
            "SELECT status, retry_count FROM ingested_sessions WHERE session_id = ?",
            (session_id,),
        ).fetchone()
        if row is None:
            return True
        status, retry_count = row
        return status == "failed" and retry_count < 3
    finally:
        conn.close()


def mark_ingested(session_id: str, agent_id: str) -> None:
    now = datetime.now(timezone.utc).isoformat()
    conn = _connect()
    try:
        conn.execute(
            """INSERT INTO ingested_sessions (session_id, agent_id, ingested_at, status)
               VALUES (?, ?, ?, 'ingested')
               ON CONFLICT(session_id) DO UPDATE SET
                 status = 'ingested', ingested_at = excluded.ingested_at""",
            (session_id, agent_id, now),
        )
        conn.commit()
    finally:
        conn.close()


def mark_failed(session_id: str, agent_id: str) -> None:
    now = datetime.now(timezone.utc).isoformat()
    conn = _connect()
    try:
        conn.execute(
            """INSERT INTO ingested_sessions (session_id, agent_id, ingested_at, status, retry_count)
               VALUES (?, ?, ?, 'failed', 1)
               ON CONFLICT(session_id) DO UPDATE SET
                 status = 'failed',
                 retry_count = retry_count + 1,
                 ingested_at = excluded.ingested_at""",
            (session_id, agent_id, now),
        )
        # Auto-abandon after 3 failures
        conn.execute(
            """UPDATE ingested_sessions
               SET status = 'abandoned'
               WHERE session_id = ? AND retry_count >= 3""",
            (session_id,),
        )
        conn.commit()
    finally:
        conn.close()
```

- [ ] **Step 2: Verify syntax**

Run: `cd /d/dotfiles && python -c "import ast; ast.parse(open('docker/cognee-skills/skills_tools/ingest_state.py').read()); print('OK')"`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add docker/cognee-skills/skills_tools/ingest_state.py
git commit -m "feat(cognee): add SQLite ingest state manager for session dedup"
```

---

## Task 2: ingest_transcript Tool

**Files:**

- Create: `docker/cognee-skills/skills_tools/ingest_transcript.py`

- [ ] **Step 1: Create ingest_transcript.py**

```python
"""ingest_transcript MCP tool — add session JSONL to Cognee knowledge graph."""

import json
import sys
from contextlib import redirect_stdout
from pathlib import Path

import mcp.types as types

from .ingest_state import is_ingested, should_retry, mark_ingested, mark_failed

MAX_FILE_SIZE = 10 * 1024 * 1024  # 10 MB
CHUNK_SIZE = 5 * 1024 * 1024  # 5 MB per chunk


async def ingest_transcript_impl(
    agent_id: str,
    session_id: str,
    file_path: str,
) -> list[types.TextContent]:
    """Read a session JSONL file and add it to Cognee for knowledge extraction.

    Deduplication is handled internally via SQLite state DB.
    Already-ingested sessions are skipped. Failed sessions are retried up to 3 times.

    Args:
        agent_id: Agent ID (e.g. "main", "slack-C0AK3SQKFV2").
        session_id: Session ID for deduplication.
        file_path: Path to the JSONL file inside the Cognee container
                   (e.g. "/openclaw-sessions/sessions/xxx.jsonl").
    """
    with redirect_stdout(sys.stderr):
        # Dedup check
        if is_ingested(session_id):
            return [types.TextContent(
                type="text",
                text=json.dumps({"status": "skipped", "reason": "already ingested", "session_id": session_id}),
            )]

        if not should_retry(session_id):
            return [types.TextContent(
                type="text",
                text=json.dumps({"status": "skipped", "reason": "abandoned after 3 failures", "session_id": session_id}),
            )]

        path = Path(file_path)
        if not path.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({"status": "error", "error": f"File not found: {file_path}"}),
            )]

        file_size = path.stat().st_size
        if file_size == 0:
            return [types.TextContent(
                type="text",
                text=json.dumps({"status": "skipped", "reason": "empty file"}),
            )]

        try:
            import cognee

            content = path.read_text(encoding="utf-8")
            dataset_name = f"sessions_{agent_id}"
            chunks_added = 0

            if file_size <= MAX_FILE_SIZE:
                await cognee.add(content, dataset_name=dataset_name)
                chunks_added = 1
            else:
                # Split into chunks for large files
                lines = content.splitlines(keepends=True)
                chunk = []
                chunk_size = 0
                for line in lines:
                    chunk.append(line)
                    chunk_size += len(line.encode("utf-8"))
                    if chunk_size >= CHUNK_SIZE:
                        await cognee.add("".join(chunk), dataset_name=dataset_name)
                        chunks_added += 1
                        chunk = []
                        chunk_size = 0
                if chunk:
                    await cognee.add("".join(chunk), dataset_name=dataset_name)
                    chunks_added += 1

            mark_ingested(session_id, agent_id)
            result = {
                "status": "ok",
                "chunks_added": chunks_added,
                "agent_id": agent_id,
                "session_id": session_id,
                "file_size_bytes": file_size,
            }
        except Exception as e:
            mark_failed(session_id, agent_id)
            result = {
                "status": "error",
                "error": str(e),
                "agent_id": agent_id,
                "session_id": session_id,
            }

        return [types.TextContent(type="text", text=json.dumps(result))]
```

- [ ] **Step 2: Verify syntax**

Run: `cd /d/dotfiles && python -c "import ast; ast.parse(open('docker/cognee-skills/skills_tools/ingest_transcript.py').read()); print('OK')"`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add docker/cognee-skills/skills_tools/ingest_transcript.py
git commit -m "feat(cognee): add ingest_transcript tool for JSONL ingestion"
```

---

## Task 3: batch_cognify Tool

**Files:**

- Create: `docker/cognee-skills/skills_tools/batch_cognify.py`

- [ ] **Step 1: Create batch_cognify.py**

```python
"""batch_cognify MCP tool — run cognee.cognify() across all pending datasets."""

import json
import sys
from contextlib import redirect_stdout

import mcp.types as types


async def batch_cognify_impl() -> list[types.TextContent]:
    """Run cognee.cognify() to build knowledge graph from all added data.

    Call this after adding multiple sessions via ingest_transcript.
    Running cognify() once for a batch is much cheaper than per-session.
    Processes all pending (un-cognified) data across all datasets.
    """
    with redirect_stdout(sys.stderr):
        try:
            import cognee

            await cognee.cognify()

            result = {"status": "ok"}
        except Exception as e:
            result = {
                "status": "error",
                "error": str(e),
            }

        return [types.TextContent(type="text", text=json.dumps(result))]
```

- [ ] **Step 2: Verify syntax**

Run: `cd /d/dotfiles && python -c "import ast; ast.parse(open('docker/cognee-skills/skills_tools/batch_cognify.py').read()); print('OK')"`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add docker/cognee-skills/skills_tools/batch_cognify.py
git commit -m "feat(cognee): add batch_cognify tool for bulk knowledge graph build"
```

---

## Task 4: search_knowledge Tool

**Files:**

- Create: `docker/cognee-skills/skills_tools/search_knowledge.py`

- [ ] **Step 1: Create search_knowledge.py**

```python
"""search_knowledge MCP tool — search Cognee knowledge graph."""

import json
import sys
from contextlib import redirect_stdout
from typing import Optional

import mcp.types as types


async def search_knowledge_impl(
    query: str,
    agent_id: Optional[str] = None,
    source: Optional[str] = None,
    limit: int = 10,
) -> list[types.TextContent]:
    """Search the Cognee knowledge graph for conversation-extracted knowledge.

    Unlike search_skill_history (which searches skill execution records),
    this searches the knowledge graph built from conversation transcripts
    (facts, decisions, lessons, relationships).

    Args:
        query: Natural language search query.
        agent_id: Filter to a specific agent (e.g. "main", "slack-C0AK3SQKFV2").
        source: Filter by source type: "sessions", "skills", or None (all).
        limit: Max results to return.
    """
    with redirect_stdout(sys.stderr):
        try:
            import cognee
            from cognee.api.v1.search import SearchType

            datasets = None
            if agent_id and source == "sessions":
                datasets = [f"sessions_{agent_id}"]
            elif agent_id:
                # Filter to this agent's session dataset only.
                # Skill execution datasets are keyed by skill_name, not agent_id,
                # so we cannot filter them by agent here.
                datasets = [f"sessions_{agent_id}"]
            # When no agent_id, search all datasets (no filter)

            results = await cognee.search(
                query_type=SearchType.CHUNKS,
                query_text=query,
                datasets=datasets,
            )

            items = []
            for r in (results or [])[:limit]:
                if isinstance(r, dict):
                    items.append(r)
                else:
                    items.append({"content": str(r)})

            result = {"status": "ok", "results": items, "count": len(items)}
        except Exception as e:
            result = {"status": "error", "error": str(e)}

        return [types.TextContent(type="text", text=json.dumps(result, default=str))]
```

- [ ] **Step 2: Verify syntax**

Run: `cd /d/dotfiles && python -c "import ast; ast.parse(open('docker/cognee-skills/skills_tools/search_knowledge.py').read()); print('OK')"`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add docker/cognee-skills/skills_tools/search_knowledge.py
git commit -m "feat(cognee): add search_knowledge tool for knowledge graph search"
```

---

## Task 5: Register New Tools in **init**.py

**Files:**

- Modify: `docker/cognee-skills/skills_tools/__init__.py`

- [ ] **Step 1: Add imports and tool registrations**

Add after the existing `rollback_skill_impl` import (line 17):

```python
    from .ingest_transcript import ingest_transcript_impl
    from .batch_cognify import batch_cognify_impl
    from .search_knowledge import search_knowledge_impl
```

Add after the `rollback_skill` tool registration (after line 45):

```python
    @mcp.tool(name="ingest_transcript", description="Ingest a session JSONL file into the Cognee knowledge graph for permanent knowledge extraction.")
    async def ingest_transcript(agent_id: str, session_id: str, file_path: str):
        return await ingest_transcript_impl(agent_id, session_id, file_path)

    @mcp.tool(name="batch_cognify", description="Run cognee.cognify() to build knowledge graph from all recently added data. Call after batch ingest_transcript calls.")
    async def batch_cognify():
        return await batch_cognify_impl()

    @mcp.tool(name="search_knowledge", description="Search the Cognee knowledge graph for conversation-extracted knowledge (facts, decisions, lessons, relationships).")
    async def search_knowledge(query: str, agent_id: str = None, source: str = None, limit: int = 10):
        return await search_knowledge_impl(query, agent_id, source, limit)
```

- [ ] **Step 2: Verify syntax**

Run: `cd /d/dotfiles && python -c "import ast; ast.parse(open('docker/cognee-skills/skills_tools/__init__.py').read()); print('OK')"`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add docker/cognee-skills/skills_tools/__init__.py
git commit -m "feat(cognee): register ingest_transcript, batch_cognify, search_knowledge tools"
```

---

## Task 6: Docker Compose Volume Mount

**Files:**

- Modify: `docker/cognee-skills/docker-compose.yml`

- [ ] **Step 1: Add openclaw-home volume mount to cognee-mcp-skills service**

In the `volumes:` section of `cognee-mcp-skills` service (after line 26 `- ${SKILLS_PATH}:/skills:rw`), add:

```yaml
- openclaw-home:/openclaw-sessions:ro
```

- [ ] **Step 2: Add external volume declaration**

In the top-level `volumes:` section (after line 74 `ollama-data:`), add:

```yaml
openclaw-home:
  external: true
  name: openclaw_openclaw-home
```

- [ ] **Step 3: Verify docker-compose syntax**

Run: `cd /d/dotfiles/docker/cognee-skills && docker compose config --quiet 2>&1 || echo "FAIL"`
Expected: No output (success) or a warning about the external volume not existing yet (acceptable).

- [ ] **Step 4: Commit**

```bash
git add docker/cognee-skills/docker-compose.yml
git commit -m "feat(cognee): mount openclaw-home volume for session JSONL access"
```

---

## Task 7: PostToolUse Hook Script

**Files:**

- Create: `docker/openclaw/hooks/log-skill-execution.js`

- [ ] **Step 1: Create hooks directory and script**

Run: `ls /d/dotfiles/docker/openclaw/hooks/ 2>/dev/null || mkdir -p /d/dotfiles/docker/openclaw/hooks`

```javascript
#!/usr/bin/env node
/**
 * PostToolUse hook: log skill tool executions to Cognee MCP.
 *
 * Reads tool name from CLAUDE_TOOL_NAME env var (Claude Code PostToolUse hook spec).
 * If the tool is an OpenClaw MCP skill tool (prefixed with "cognee-skills__"),
 * sends a JSON-RPC call to the Cognee MCP Streamable HTTP endpoint to log the execution.
 *
 * Errors are logged to stderr and never block the agent response.
 */

const COGNEE_MCP_URL = process.env.COGNEE_MCP_URL || "http://cognee-mcp-skills:8000/mcp";
const SKILL_TOOL_PREFIX = "cognee-skills__";

async function main() {
  const toolName = process.env.CLAUDE_TOOL_NAME;
  if (!toolName) return;

  // Only log executions of skill-related tools, not the self-improvement tools themselves
  const skipTools = [
    "log_skill_execution",
    "search_skill_history",
    "get_skill_status",
    "get_skill_improvements",
    "amend_skill",
    "evaluate_amendment",
    "rollback_skill",
    "ingest_transcript",
    "batch_cognify",
    "search_knowledge",
  ];

  // Check if this is a skill tool execution
  let skillName = null;
  if (toolName.startsWith(SKILL_TOOL_PREFIX)) {
    const shortName = toolName.slice(SKILL_TOOL_PREFIX.length);
    if (skipTools.includes(shortName)) return;
    skillName = shortName;
  } else {
    // Not a cognee-skills MCP tool, skip
    return;
  }

  const toolResult = process.env.CLAUDE_TOOL_RESULT || "";
  const success = !toolResult.toLowerCase().includes('"error"');

  const rpcPayload = {
    jsonrpc: "2.0",
    id: Date.now(),
    method: "tools/call",
    params: {
      name: "log_skill_execution",
      arguments: {
        skill_name: skillName,
        agent: "openclaw-hook",
        task_description: `Auto-logged by PostToolUse hook for tool: ${toolName}`,
        success: success,
        error: success ? null : "Tool result contained error indicator",
      },
    },
  };

  try {
    const resp = await fetch(COGNEE_MCP_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(rpcPayload),
      signal: AbortSignal.timeout(5000),
    });
    if (!resp.ok) {
      console.error(`[log-skill-hook] HTTP ${resp.status}: ${await resp.text()}`);
    }
  } catch (err) {
    console.error(`[log-skill-hook] ${err.message}`);
  }
}

main().catch((err) => console.error(`[log-skill-hook] ${err.message}`));
```

- [ ] **Step 2: Commit**

```bash
git add docker/openclaw/hooks/log-skill-execution.js
git commit -m "feat(openclaw): add PostToolUse hook for automatic skill execution logging"
```

---

## Task 8: OpenClaw Dockerfile — COPY Hooks

**Files:**

- Modify: `docker/openclaw/Dockerfile:13`

- [ ] **Step 1: Add COPY for hooks directory**

After line 13 (`COPY tests/ /app/tests/`), add:

```dockerfile
COPY hooks/ /app/data/hooks/
```

- [ ] **Step 2: Verify Dockerfile syntax**

Run: `cd /d/dotfiles/docker/openclaw && docker build --check . 2>&1 | head -5 || echo "docker build --check not supported, skip"`

Note: If `--check` is not supported, just verify the COPY line is syntactically correct by reading the file.

- [ ] **Step 3: Commit**

```bash
git add docker/openclaw/Dockerfile
git commit -m "feat(openclaw): copy hooks/ into image at build time"
```

---

## Task 9: Entrypoint — AGENTS.md Feedback Rules + PostToolUse Hook Wiring

**Files:**

- Modify: `docker/openclaw/entrypoint.sh`

- [ ] **Step 1: Add Cognee feedback rules block**

After the `## END SANDBOX RULES` block (before `fi # end: workspace_agents writable check`), add:

```bash
  # Inject Cognee skill feedback rules.
  if ! grep -q "BEGIN COGNEE FEEDBACK RULES" "$workspace_agents"; then
    cat >>"$workspace_agents" <<'EOF'

## BEGIN COGNEE FEEDBACK RULES

- `/feedback <スキル名> <問題内容>` コマンドでスキルのフィードバックを記録できる
- フィードバック記録時は cognee-skills MCP の `log_skill_execution` を
  `success=false, error="ユーザー指摘: <問題内容>"` で呼び出すこと
- スコアが閾値以下に下がると自動改善が発火する

## END COGNEE FEEDBACK RULES
EOF
  fi
```

- [ ] **Step 2: Wire PostToolUse hook into Claude Code settings.json**

Find the Claude Code setup section in entrypoint.sh (around the `# --- Claude Code ---` comment area). Add after the existing Claude config setup:

```bash
# --- PostToolUse hook for skill execution logging ---
_claude_settings="/home/app/.claude/settings.json"
if [ -f "$_claude_settings" ]; then
  # Merge PostToolUse hook into existing settings
  if ! grep -q "log-skill-execution" "$_claude_settings" 2>/dev/null; then
    _tmp=$(mktemp)
    node -e "
      const fs = require('fs');
      const s = JSON.parse(fs.readFileSync('$_claude_settings', 'utf8'));
      s.hooks = s.hooks || {};
      s.hooks.PostToolUse = s.hooks.PostToolUse || [];
      s.hooks.PostToolUse.push({ matcher: '', hooks: [{ type: 'command', command: 'node /app/data/hooks/log-skill-execution.js' }] });
      fs.writeFileSync('$_tmp', JSON.stringify(s, null, 2));
    " && mv "$_tmp" "$_claude_settings"
    echo "[entrypoint] PostToolUse hook wired into Claude Code settings"
  fi
else
  # Create minimal settings with hook
  cat > "$_claude_settings" <<'HOOKEOF'
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "node /app/data/hooks/log-skill-execution.js"
          }
        ]
      }
    ]
  }
}
HOOKEOF
  echo "[entrypoint] created Claude Code settings with PostToolUse hook"
fi
```

- [ ] **Step 3: Verify entrypoint syntax**

Run: `bash -n /d/dotfiles/docker/openclaw/entrypoint.sh && echo "OK"`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add docker/openclaw/entrypoint.sh
git commit -m "feat(openclaw): inject Cognee feedback rules and wire PostToolUse hook"
```

---

## Task 10: OpenClaw Config — initialHistoryLimit

**Files:**

- Modify: `chezmoi/.chezmoidata/openclaw.yaml:97`
- Modify: `chezmoi/dot_openclaw/openclaw.docker.json.tmpl:254-257`

- [ ] **Step 1: Add slackThreadInitialHistoryLimit to openclaw.yaml**

After line 97 (`slackHistoryLimit: 100`), add:

```yaml
slackThreadInitialHistoryLimit: 50
```

- [ ] **Step 2: Add initialHistoryLimit to thread config in openclaw.docker.json.tmpl**

Change the `"thread"` section (lines 254-257) from:

```json
      "thread": {
        "historyScope": "thread",
        "inheritParent": false
      }
```

To:

```json
      "thread": {
        "historyScope": "thread",
        "inheritParent": false,
        "initialHistoryLimit": {{ .openclaw.channels.slackThreadInitialHistoryLimit }}
      }
```

- [ ] **Step 3: Verify chezmoi template renders**

Run: `cd /d/dotfiles && chezmoi execute-template < chezmoi/dot_openclaw/openclaw.docker.json.tmpl 2>&1 | python -m json.tool > /dev/null && echo "OK"`

Note: This may fail if 1Password is not signed in. In that case, check the diff manually.

- [ ] **Step 4: Commit**

```bash
git add chezmoi/.chezmoidata/openclaw.yaml chezmoi/dot_openclaw/openclaw.docker.json.tmpl
git commit -m "feat(openclaw): add initialHistoryLimit for Slack thread context restoration"
```

---

## Task 11: Cron Job — cognee-daily-ingest

**Files:**

- Modify: `chezmoi/dot_openclaw/cron/jobs.seed.json.tmpl:101`

- [ ] **Step 1: Add cognee-daily-ingest job**

Before the closing `]` of the `"jobs"` array (line 102), add a comma after the last job object (line 101 `}`), then add:

```jsonc
    ,
    {
      "id": "d1e2f3a4-cognee-ingest-0001-000000000001",
      "agentId": "main",
      "name": "cognee-daily-ingest",
      "enabled": true,
      "createdAtMs": 1774310400000,
      "updatedAtMs": 1774310400000,
      "schedule": {
        "kind": "cron",
        "expr": "50 23 * * *",
        "tz": "Asia/Tokyo"
      },
      "sessionTarget": "isolated",
      "wakeMode": "now",
      "payload": {
        "kind": "agentTurn",
        "message": "Cognee daily ingest & skill improvement run.\n\n1. Find all session JSONL files: `find /home/app/.openclaw -name '*.jsonl' -type f`\n2. For each file, extract agent_id and session_id from the path.\n3. Call cognee-skills MCP `ingest_transcript` for each session.\n   - Deduplication is handled automatically inside the tool (already-ingested sessions are skipped).\n   - IMPORTANT: Translate the path from OpenClaw container path to Cognee container path:\n     /home/app/.openclaw/... → /openclaw-sessions/...\n4. After all sessions are added, call `batch_cognify` to build the knowledge graph.\n5. Call `search_knowledge` with queries: \"user complaint\", \"error\", \"skill failure\", \"feedback\".\n6. For each skill mentioned in results, call `get_skill_status`. If score < 0.7, run `get_skill_improvements` then `amend_skill`.\n7. Do NOT send any message unless skills were improved or errors occurred."
      },
      "delivery": {
        "mode": "silent"
      }
    }
```

- [ ] **Step 2: Verify JSON template syntax**

Run: `cd /d/dotfiles && chezmoi execute-template < chezmoi/dot_openclaw/cron/jobs.seed.json.tmpl 2>&1 | python -m json.tool > /dev/null && echo "OK"`

Note: May fail if 1Password is not signed in. Check diff manually if so.

- [ ] **Step 3: Commit**

```bash
git add chezmoi/dot_openclaw/cron/jobs.seed.json.tmpl
git commit -m "feat(openclaw): add cognee-daily-ingest cron job"
```

---

## Task 12: Documentation Update

**Files:**

- Modify: `docs/chezmoi/dot_openclaw/07-channels.md`

- [ ] **Step 1: Add initialHistoryLimit documentation**

After the `thread.inheritParent` row in the Slack settings table (or at the end of the Slack section), add:

```markdown
### Slack スレッドの文脈復元

| キー                         | 値   | 説明                                                                      |
| ---------------------------- | ---- | ------------------------------------------------------------------------- |
| `thread.initialHistoryLimit` | `50` | セッションリセット後に Slack API から取得するスレッド内メッセージ数の上限 |

`historyLimit` (セッション全体の履歴上限) とは異なり、`initialHistoryLimit` は新セッション開始時にスレッドの文脈を復元するために使用される。
```

- [ ] **Step 2: Commit**

```bash
git add docs/chezmoi/dot_openclaw/07-channels.md
git commit -m "docs: add initialHistoryLimit documentation"
```

---

## Task 13: Integration Verification

- [ ] **Step 1: Docker Compose config validation (cognee-skills)**

Run: `cd /d/dotfiles/docker/cognee-skills && docker compose config --quiet 2>&1; echo "exit: $?"`
Expected: Exit 0 or warning about missing external volume (acceptable pre-deploy).

- [ ] **Step 2: Docker build dry-run (openclaw)**

Run: `cd /d/dotfiles/docker/openclaw && docker build --no-cache --progress=plain . 2>&1 | tail -20`
Expected: Build succeeds. Verify the `COPY hooks/ /app/data/hooks/` step appears.

- [ ] **Step 3: Docker build dry-run (cognee-skills)**

Run: `cd /d/dotfiles/docker/cognee-skills && docker build --no-cache --progress=plain . 2>&1 | tail -20`
Expected: Build succeeds with new Python files included.

- [ ] **Step 4: Python import check**

Run: `cd /d/dotfiles && python -c "
import ast
files = [
    'docker/cognee-skills/skills_tools/__init__.py',
    'docker/cognee-skills/skills_tools/ingest_state.py',
    'docker/cognee-skills/skills_tools/ingest_transcript.py',
    'docker/cognee-skills/skills_tools/batch_cognify.py',
    'docker/cognee-skills/skills_tools/search_knowledge.py',
]
for f in files:
    ast.parse(open(f).read())
    print(f'OK: {f}')
"`
Expected: All 5 files print `OK`.

- [ ] **Step 5: Verify entrypoint.sh syntax**

Run: `bash -n /d/dotfiles/docker/openclaw/entrypoint.sh && echo "OK"`
Expected: `OK`

- [ ] **Step 6: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix: address integration issues from verification"
```
