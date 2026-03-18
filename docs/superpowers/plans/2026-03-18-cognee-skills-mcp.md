# cognee-skills MCP Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Docker MCP server that tracks skill executions and automatically improves skills based on failure patterns, accessible from all AI agents.

**Architecture:** Fork cognee-mcp, add 7 custom tools for skill lifecycle management (log → search → status → improve → amend → evaluate → rollback), backed by FalkorDB for hybrid graph+vector storage. Deploy as HTTP MCP server in Docker, connect all agents via unified `mcp_servers.yaml`.

**Tech Stack:** Python 3.12, cognee SDK, FastMCP, FalkorDB, Docker Compose, chezmoi, PowerShell

**Spec:** `docs/superpowers/specs/2026-03-18-cognee-skills-mcp-design.md`

---

## File Structure

```
docker/cognee-skills/                    ← 新規ディレクトリ
├── docker-compose.yml                   ← コンテナ定義（cognee-mcp-skills + FalkorDB + Ollama）
├── Dockerfile                           ← cognee-mcp フォーク + カスタムツール
├── entrypoint.sh                        ← secret 読み取り + 起動
├── .env.example                         ← 環境変数テンプレート
└── skills_tools/                        ← カスタム MCP ツール
    ├── __init__.py                      ← ツール登録（@mcp.tool デコレータ）
    ├── models.py                        ← cognee Custom DataPoint 定義
    ├── health.py                        ← 健全性スコア計算
    ├── log_execution.py                 ← log_skill_execution ツール
    ├── search_history.py                ← search_skill_history ツール
    ├── skill_status.py                  ← get_skill_status ツール
    ├── improvements.py                  ← get_skill_improvements ツール
    ├── amend.py                         ← amend_skill ツール
    ├── evaluate.py                      ← evaluate_amendment ツール
    └── rollback.py                      ← rollback_skill ツール

chezmoi/.chezmoidata/mcp_servers.yaml    ← cognee-skills エントリ追加
chezmoi/dot_openclaw/openclaw.docker.json.tmpl  ← OpenClaw MCP 設定追加
docker/openclaw/docker-compose.yml       ← cognee-network 追加
scripts/powershell/handlers/Handler.CogneeSkills.ps1  ← ハンドラー新規作成
```

---

### Task 1: Docker インフラ（docker-compose + Dockerfile + entrypoint）

**Files:**
- Create: `docker/cognee-skills/docker-compose.yml`
- Create: `docker/cognee-skills/Dockerfile`
- Create: `docker/cognee-skills/entrypoint.sh`
- Create: `docker/cognee-skills/.env.example`

- [ ] **Step 1: ディレクトリ作成**

```bash
mkdir -p docker/cognee-skills/skills_tools
```

- [ ] **Step 2: .env.example 作成**

```bash
cat > docker/cognee-skills/.env.example << 'EOF'
LLM_PROVIDER=gemini
EMBEDDING_PROVIDER=gemini
EMBEDDING_MODEL=gemini-embedding-2-preview
SKILLS_PATH=../../chezmoi/dot_claude/skills
OPENCLAW_GEMINI_API_KEY_FILE=~/.openclaw/secrets/gemini_api_key
SKILL_HEALTH_WINDOW=20
SKILL_HEALTH_THRESHOLD=0.7
SKILL_CORRECTION_PENALTY=0.05
EOF
```

- [ ] **Step 3: Dockerfile 作成**

cognee-mcp 公式 Dockerfile をベースに、FalkorDB アダプタとカスタムツールを追加。

```dockerfile
# syntax=docker/dockerfile:1
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS builder

WORKDIR /app

# cognee-mcp をクローン（特定コミットを pin）
RUN apt-get update && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*
ARG COGNEE_COMMIT=main
RUN git clone https://github.com/topoteretes/cognee.git /app/cognee \
    && cd /app/cognee && git checkout ${COGNEE_COMMIT}

# cognee SDK + FalkorDB アダプタをインストール
WORKDIR /app/cognee
RUN uv venv /app/.venv \
    && uv pip install --python /app/.venv/bin/python \
       -e ".[falkordb]" \
       cognee-community-hybrid-adapter-falkor

# cognee-mcp をインストール
WORKDIR /app/cognee/cognee-mcp
RUN uv pip install --python /app/.venv/bin/python -e .

# カスタムツールをコピー
COPY skills_tools/ /app/cognee/cognee-mcp/src/skills_tools/

# --- runtime stage ---
FROM python:3.12-slim-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
      libpq5 git \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/.venv /app/.venv
COPY --from=builder /app/cognee /app/cognee
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh \
    && sed -i 's/\r$//' /app/entrypoint.sh

ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1

WORKDIR /app/cognee/cognee-mcp
EXPOSE 8000

ENTRYPOINT ["/app/entrypoint.sh"]
```

- [ ] **Step 4: entrypoint.sh 作成**

```bash
#!/bin/sh
set -e

# Read Gemini API key from Docker secret
_gemini_secret="/run/secrets/gemini_api_key"
if [ -f "$_gemini_secret" ]; then
  _key=$(cat "$_gemini_secret")
  if [ -n "$_key" ]; then
    export LLM_API_KEY="$_key"
    export EMBEDDING_API_KEY="$_key"
    echo "[entrypoint] GEMINI_API_KEY loaded from secret"
  fi
fi

# FalkorDB adapter registration
export COGNEE_FALKORDB_AUTO_REGISTER=1

echo "[entrypoint] starting cognee-mcp-skills (transport=${TRANSPORT_MODE:-http})"
exec python src/server.py --transport "${TRANSPORT_MODE:-http}" --host 0.0.0.0 --port 8000
```

- [ ] **Step 5: docker-compose.yml 作成**

```yaml
services:
  cognee-mcp-skills:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "8000:8000"
    environment:
      - TRANSPORT_MODE=http
      - LLM_PROVIDER=${LLM_PROVIDER:-gemini}
      - EMBEDDING_PROVIDER=${EMBEDDING_PROVIDER:-gemini}
      - EMBEDDING_MODEL=${EMBEDDING_MODEL:-gemini-embedding-2-preview}
      - GRAPH_DATABASE_PROVIDER=falkordb
      - GRAPH_DATABASE_URL=falkordb
      - GRAPH_DATABASE_PORT=6379
      - VECTOR_DB_PROVIDER=falkordb
      - VECTOR_DB_URL=falkordb
      - VECTOR_DB_PORT=6379
      - SKILL_HEALTH_WINDOW=${SKILL_HEALTH_WINDOW:-20}
      - SKILL_HEALTH_THRESHOLD=${SKILL_HEALTH_THRESHOLD:-0.7}
      - SKILL_CORRECTION_PENALTY=${SKILL_CORRECTION_PENALTY:-0.05}
    secrets:
      - gemini_api_key
    depends_on:
      falkordb:
        condition: service_healthy
    volumes:
      - ${SKILLS_PATH}:/skills:rw
    networks:
      - cognee-network
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    restart: unless-stopped

  falkordb:
    image: falkordb/falkordb:v4.4.1
    ports:
      - "${FALKORDB_PORT:-6379}:6379"
    volumes:
      - falkordb-data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 3
    networks:
      - cognee-network
    restart: unless-stopped

  ollama:
    image: ollama/ollama:latest
    profiles: ["local"]
    ports:
      - "11434:11434"
    volumes:
      - ollama-data:/root/.ollama
    networks:
      - cognee-network
    restart: unless-stopped

networks:
  cognee-network:
    driver: bridge

volumes:
  falkordb-data:
  ollama-data:

secrets:
  gemini_api_key:
    file: ${OPENCLAW_GEMINI_API_KEY_FILE}
```

- [ ] **Step 6: ビルドして FalkorDB 接続を確認**

```bash
cd docker/cognee-skills
cp .env.example .env
# OPENCLAW_GEMINI_API_KEY_FILE と SKILLS_PATH を実際のパスに編集
docker compose up -d falkordb
docker compose exec falkordb redis-cli ping
```

Expected: `PONG`

- [ ] **Step 7: cognee-mcp-skills をビルドして起動確認**

```bash
docker compose up -d --build cognee-mcp-skills
curl http://localhost:8000/health
```

Expected: `{"status": "ok"}`

- [ ] **Step 8: コミット**

```bash
git add docker/cognee-skills/
git commit -m "feat(cognee-skills): add Docker infra for cognee-mcp-skills + FalkorDB"
```

---

### Task 2: データモデル（cognee Custom DataPoints）

**Files:**
- Create: `docker/cognee-skills/skills_tools/models.py`
- Create: `docker/cognee-skills/skills_tools/__init__.py`

- [ ] **Step 1: models.py を作成**

cognee の Custom DataPoint を使ってグラフノードを定義する。

```python
"""Custom DataPoint definitions for skill improvement graph."""
from datetime import datetime
from enum import Enum
from typing import Optional
from uuid import uuid4

from cognee.infrastructure.engine import DataPoint


class AmendmentStatus(str, Enum):
    PROPOSED = "proposed"
    APPLIED = "applied"
    ROLLED_BACK = "rolled_back"
    FAILED = "failed"


class FeedbackType(str, Enum):
    USER_CORRECTION = "user_correction"
    AUTO = "auto"


class Skill(DataPoint):
    __tablename__ = "skills"
    name: str
    source_path: str
    agent_type: str  # claude/codex/cursor/openclaw/gemini

    _metadata = {"index_fields": ["name"], "type": "Skill"}


class SkillVersion(DataPoint):
    __tablename__ = "skill_versions"
    skill_id: str
    version: int
    content: str  # full skill directory content (JSON-serialized)
    content_hash: str
    created_at: datetime

    _metadata = {"index_fields": ["skill_id", "version"], "type": "SkillVersion"}


class Execution(DataPoint):
    __tablename__ = "executions"
    skill_id: str
    agent: str
    task_description: str
    success: bool
    error: Optional[str] = None
    duration_ms: Optional[int] = None
    timestamp: datetime

    _metadata = {"index_fields": ["skill_id", "agent", "success"], "type": "Execution"}


class Feedback(DataPoint):
    __tablename__ = "feedbacks"
    execution_id: str
    feedback_type: FeedbackType
    message: str
    timestamp: datetime

    _metadata = {"index_fields": ["execution_id"], "type": "Feedback"}


class Amendment(DataPoint):
    __tablename__ = "amendments"
    skill_id: str
    diff: str
    rationale: str
    status: AmendmentStatus = AmendmentStatus.PROPOSED
    score_before: Optional[float] = None
    score_after: Optional[float] = None
    version_before: Optional[int] = None
    version_after: Optional[int] = None
    created_at: datetime

    _metadata = {"index_fields": ["skill_id", "status"], "type": "Amendment"}
```

- [ ] **Step 2: `__init__.py` を作成（空のプレースホルダー）**

```python
"""Skills tools package - custom MCP tools for skill improvement."""
```

- [ ] **Step 3: コミット**

```bash
git add docker/cognee-skills/skills_tools/models.py docker/cognee-skills/skills_tools/__init__.py
git commit -m "feat(cognee-skills): add data model definitions (Custom DataPoints)"
```

---

### Task 3: 健全性スコア計算

**Files:**
- Create: `docker/cognee-skills/skills_tools/health.py`

- [ ] **Step 1: health.py を作成**

```python
"""Skill health score calculation."""
import os


def get_config():
    """Load health score configuration from environment."""
    return {
        "window": int(os.environ.get("SKILL_HEALTH_WINDOW", "20")),
        "threshold": float(os.environ.get("SKILL_HEALTH_THRESHOLD", "0.7")),
        "correction_penalty": float(os.environ.get("SKILL_CORRECTION_PENALTY", "0.05")),
    }


def calculate_health_score(
    executions: list[dict],
    correction_count: int,
) -> float:
    """Calculate skill health score.

    score = success_rate - (correction_count * penalty)
    Clamped to [0.0, 1.0].

    Args:
        executions: List of recent executions with 'success' bool field.
        correction_count: Number of user correction feedbacks.

    Returns:
        Health score between 0.0 and 1.0.
    """
    config = get_config()

    if not executions:
        return 1.0

    # Use only the most recent N executions
    recent = executions[-config["window"] :]
    success_count = sum(1 for e in recent if e.get("success", False))
    success_rate = success_count / len(recent)

    score = success_rate - (correction_count * config["correction_penalty"])
    return max(0.0, min(1.0, score))


def needs_improvement(score: float) -> bool:
    """Check if a skill's health score is below the improvement threshold."""
    config = get_config()
    return score < config["threshold"]
```

- [ ] **Step 2: コミット**

```bash
git add docker/cognee-skills/skills_tools/health.py
git commit -m "feat(cognee-skills): add health score calculation"
```

---

### Task 4: log_skill_execution ツール

**Files:**
- Create: `docker/cognee-skills/skills_tools/log_execution.py`

- [ ] **Step 1: log_execution.py を作成**

```python
"""log_skill_execution MCP tool."""
import asyncio
import json
import os
from contextlib import redirect_stdout
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional
from uuid import uuid4

import sys
import mcp.types as types

from .models import Execution, Skill
from .health import calculate_health_score, needs_improvement

# Rate limiting: track last amendment time per skill
_last_amendment: dict[str, datetime] = {}
_consecutive_failures: dict[str, int] = {}
_auto_amend_disabled: set[str] = set()

BUFFER_DIR = Path("/tmp/skill-logs")


async def log_skill_execution_impl(
    skill_name: str,
    agent: str,
    task_description: str,
    success: bool,
    error: Optional[str] = None,
    duration_ms: Optional[int] = None,
) -> list[types.TextContent]:
    """Log a skill execution result for tracking and improvement.

    Args:
        skill_name: Name of the skill that was executed.
        agent: Agent that executed the skill (claude-code, codex, cursor, etc.).
        task_description: What the skill was used for.
        success: Whether the execution succeeded.
        error: Error message if failed.
        duration_ms: Execution duration in milliseconds.
    """
    with redirect_stdout(sys.stderr):
        now = datetime.now(timezone.utc)
        execution_id = str(uuid4())

        # Build execution DataPoint
        execution = Execution(
            id=execution_id,
            skill_id=skill_name,
            agent=agent,
            task_description=task_description,
            success=success,
            error=error,
            duration_ms=duration_ms,
            timestamp=now,
        )

        try:
            import cognee

            # Persist execution as Custom DataPoint via cognify
            await cognee.add(
                json.dumps(execution.model_dump(), default=str),
                dataset_name=f"skill_{skill_name}_executions",
            )
            await cognee.cognify()

            # --- Auto-improvement trigger ---
            if skill_name not in _auto_amend_disabled:
                exec_results = await cognee.search(
                    query_type="CHUNKS",
                    query_text=f"skill_id:{skill_name}",
                    datasets=[f"skill_{skill_name}_executions"],
                )
                executions = exec_results or []
                score = calculate_health_score(executions, 0)

                if needs_improvement(score):
                    # Rate limit: 1 amendment per skill per 24h
                    last = _last_amendment.get(skill_name)
                    if last and (now - last).total_seconds() < 86400:
                        pass  # Skip, too soon
                    else:
                        # Import and call improvements inline
                        from .improvements import get_skill_improvements_impl
                        asyncio.create_task(
                            get_skill_improvements_impl(skill_name, min_executions=5)
                        )
                        _last_amendment[skill_name] = now

        except Exception as e:
            # FalkorDB down: buffer to local file
            BUFFER_DIR.mkdir(parents=True, exist_ok=True)
            buf_file = BUFFER_DIR / f"{execution_id}.json"
            buf_file.write_text(json.dumps(execution.model_dump(), default=str))
            print(f"[log_execution] FalkorDB unavailable, buffered to {buf_file}", file=sys.stderr)

        result = {
            "status": "logged",
            "execution_id": execution_id,
            "skill_name": skill_name,
            "success": success,
        }

        return [types.TextContent(type="text", text=json.dumps(result))]
```

- [ ] **Step 2: コミット**

```bash
git add docker/cognee-skills/skills_tools/log_execution.py
git commit -m "feat(cognee-skills): add log_skill_execution tool"
```

---

### Task 5: search_skill_history + get_skill_status ツール

**Files:**
- Create: `docker/cognee-skills/skills_tools/search_history.py`
- Create: `docker/cognee-skills/skills_tools/skill_status.py`

- [ ] **Step 1: search_history.py を作成**

```python
"""search_skill_history MCP tool."""
import json
from contextlib import redirect_stdout
from typing import Optional

import sys
import mcp.types as types


async def search_skill_history_impl(
    skill_name: Optional[str] = None,
    agent: Optional[str] = None,
    success: Optional[bool] = None,
    limit: int = 20,
) -> list[types.TextContent]:
    """Search past skill execution history.

    Args:
        skill_name: Filter by skill name (optional).
        agent: Filter by agent (optional).
        success: Filter by success/failure (optional).
        limit: Maximum results to return.
    """
    with redirect_stdout(sys.stderr):
        import cognee
        from cognee.api.v1.search import SearchType

        query_parts = []
        if skill_name:
            query_parts.append(f"skill:{skill_name}")
        if agent:
            query_parts.append(f"agent:{agent}")
        if success is not None:
            query_parts.append(f"success:{success}")
        query_parts.append("type:execution")

        query = " ".join(query_parts) if query_parts else "type:execution"

        results = await cognee.search(
            query_type=SearchType.CHUNKS,
            query_text=query,
            datasets=[f"skill_{skill_name}_executions"] if skill_name else None,
        )

        # Limit results
        limited = results[:limit] if results else []

        return [types.TextContent(type="text", text=json.dumps(limited, default=str))]
```

- [ ] **Step 2: skill_status.py を作成**

```python
"""get_skill_status MCP tool."""
import json
from contextlib import redirect_stdout
from typing import Optional

import sys
import mcp.types as types

from .health import calculate_health_score, needs_improvement


async def get_skill_status_impl(
    skill_name: str,
) -> list[types.TextContent]:
    """Get the health status summary of a skill.

    Args:
        skill_name: Name of the skill to check.
    """
    with redirect_stdout(sys.stderr):
        import cognee
        from cognee.api.v1.search import SearchType

        # Fetch recent executions
        exec_results = await cognee.search(
            query_type=SearchType.CHUNKS,
            query_text=f"skill:{skill_name} type:execution",
            datasets=[f"skill_{skill_name}_executions"],
        )

        executions = exec_results if exec_results else []

        # Count corrections
        feedback_results = await cognee.search(
            query_type=SearchType.CHUNKS,
            query_text=f"skill:{skill_name} type:feedback feedback_type:user_correction",
        )
        correction_count = len(feedback_results) if feedback_results else 0

        # Calculate health
        score = calculate_health_score(executions, correction_count)

        # Find failure patterns
        failures = [e for e in executions if not e.get("success", True)]
        error_messages = [f.get("error", "unknown") for f in failures[-5:]]

        # Check for pending amendments
        amendment_results = await cognee.search(
            query_type=SearchType.CHUNKS,
            query_text=f"skill:{skill_name} type:amendment status:proposed",
        )

        status = {
            "skill_name": skill_name,
            "health_score": round(score, 3),
            "needs_improvement": needs_improvement(score),
            "total_executions": len(executions),
            "recent_failures": len(failures),
            "recent_error_patterns": error_messages,
            "pending_amendments": len(amendment_results) if amendment_results else 0,
        }

        return [types.TextContent(type="text", text=json.dumps(status))]
```

- [ ] **Step 3: コミット**

```bash
git add docker/cognee-skills/skills_tools/search_history.py docker/cognee-skills/skills_tools/skill_status.py
git commit -m "feat(cognee-skills): add search_skill_history and get_skill_status tools"
```

---

### Task 6: 改善系ツール（get_skill_improvements + amend_skill）

**Files:**
- Create: `docker/cognee-skills/skills_tools/improvements.py`
- Create: `docker/cognee-skills/skills_tools/amend.py`

- [ ] **Step 1: improvements.py を作成**

```python
"""get_skill_improvements MCP tool."""
import json
import os
from contextlib import redirect_stdout
from datetime import datetime, timezone
from typing import Optional
from uuid import uuid4

import sys
import mcp.types as types

from .health import calculate_health_score


async def get_skill_improvements_impl(
    skill_name: str,
    min_executions: int = 5,
) -> list[types.TextContent]:
    """Generate improvement proposals based on execution history.

    Analyzes failure patterns and proposes SKILL.md amendments.

    Args:
        skill_name: Name of the skill to improve.
        min_executions: Minimum executions required before proposing improvements.
    """
    with redirect_stdout(sys.stderr):
        import cognee
        from cognee.api.v1.search import SearchType

        # Fetch execution history
        exec_results = await cognee.search(
            query_type=SearchType.CHUNKS,
            query_text=f"skill:{skill_name} type:execution",
            datasets=[f"skill_{skill_name}_executions"],
        )

        executions = exec_results if exec_results else []

        if len(executions) < min_executions:
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "status": "insufficient_data",
                    "message": f"Need at least {min_executions} executions, have {len(executions)}",
                }),
            )]

        # Read current skill content from mounted volume
        skill_dir = f"/skills/{skill_name}"
        skill_md_path = f"{skill_dir}/SKILL.md"

        if not os.path.exists(skill_md_path):
            return [types.TextContent(
                type="text",
                text=json.dumps({"status": "error", "message": f"SKILL.md not found at {skill_md_path}"}),
            )]

        with open(skill_md_path) as f:
            current_content = f.read()

        # Gather failure details
        failures = [e for e in executions if not e.get("success", True)]
        failure_summary = "\n".join(
            f"- Error: {f.get('error', 'unknown')} (agent: {f.get('agent', '?')}, task: {f.get('task_description', '?')})"
            for f in failures[-10:]
        )

        # Use cognee's LLM to generate improvement proposal
        improvement_query = f"""Analyze this skill and its failure patterns, then propose specific improvements.

CURRENT SKILL.md:
{current_content}

RECENT FAILURES ({len(failures)} of {len(executions)} total):
{failure_summary}

Propose a unified diff that fixes the most common failure patterns.
Include rationale for each change.
Output JSON with fields: "diff" (unified diff string), "rationale" (explanation)."""

        proposal = await cognee.search(
            query_type=SearchType.RAG_COMPLETION,
            query_text=improvement_query,
        )

        # Store amendment proposal
        amendment_id = f"amd_{uuid4().hex[:12]}"
        score = calculate_health_score(executions, 0)

        amendment_data = json.dumps({
            "type": "amendment",
            "amendment_id": amendment_id,
            "skill_name": skill_name,
            "status": "proposed",
            "score_before": round(score, 3),
            "proposal": proposal[0] if proposal else "No proposal generated",
            "created_at": datetime.now(timezone.utc).isoformat(),
        })

        await cognee.add(amendment_data, dataset_name=f"skill_{skill_name}_amendments")
        await cognee.cognify()

        result = {
            "status": "proposal_generated",
            "amendment_id": amendment_id,
            "skill_name": skill_name,
            "score_before": round(score, 3),
            "failure_count": len(failures),
            "proposal": proposal[0] if proposal else None,
        }

        return [types.TextContent(type="text", text=json.dumps(result, default=str))]
```

- [ ] **Step 2: amend.py を作成**

```python
"""amend_skill MCP tool."""
import hashlib
import json
import os
import shutil
from contextlib import redirect_stdout
from datetime import datetime, timezone

import sys
import mcp.types as types


async def amend_skill_impl(
    amendment_id: str,
) -> list[types.TextContent]:
    """Apply a proposed skill amendment.

    Reads the amendment proposal from the graph, applies the changes
    to the skill directory, and creates a new SkillVersion.

    Args:
        amendment_id: The amendment ID to apply.
    """
    with redirect_stdout(sys.stderr):
        import cognee
        from cognee.api.v1.search import SearchType

        # Fetch amendment
        results = await cognee.search(
            query_type=SearchType.CHUNKS,
            query_text=f"amendment_id:{amendment_id} type:amendment",
        )

        if not results:
            return [types.TextContent(
                type="text",
                text=json.dumps({"status": "error", "message": f"Amendment {amendment_id} not found"}),
            )]

        amendment = results[0] if isinstance(results[0], dict) else json.loads(str(results[0]))
        skill_name = amendment.get("skill_name", "")
        skill_dir = f"/skills/{skill_name}"
        skill_md_path = f"{skill_dir}/SKILL.md"

        if not os.path.exists(skill_md_path):
            return [types.TextContent(
                type="text",
                text=json.dumps({"status": "error", "message": f"Skill directory not found: {skill_dir}"}),
            )]

        # Backup current version
        with open(skill_md_path) as f:
            original_content = f.read()

        # Store version snapshot in graph before modifying
        version_data = json.dumps({
            "type": "skill_version",
            "skill_name": skill_name,
            "content": original_content,
            "content_hash": hashlib.sha256(original_content.encode()).hexdigest(),
            "created_at": datetime.now(timezone.utc).isoformat(),
            "amendment_id": amendment_id,
        })

        await cognee.add(version_data, dataset_name=f"skill_{skill_name}_versions")

        # Apply the amendment (extract new content from proposal)
        proposal = amendment.get("proposal", "")

        # Write amended content
        try:
            # The proposal should contain the updated SKILL.md content
            # For now, write the proposal as-is; the LLM in get_skill_improvements
            # should have generated proper content
            if isinstance(proposal, str) and proposal.strip():
                with open(skill_md_path, "w") as f:
                    f.write(proposal)
            else:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({"status": "error", "message": "Empty proposal content"}),
                )]
        except OSError as e:
            # Update amendment status to failed
            fail_data = json.dumps({
                "type": "amendment",
                "amendment_id": amendment_id,
                "status": "failed",
                "error": str(e),
            })
            await cognee.add(fail_data, dataset_name=f"skill_{skill_name}_amendments")
            await cognee.cognify()

            return [types.TextContent(
                type="text",
                text=json.dumps({"status": "failed", "error": str(e)}),
            )]

        # Update amendment status
        applied_data = json.dumps({
            "type": "amendment",
            "amendment_id": amendment_id,
            "status": "applied",
            "applied_at": datetime.now(timezone.utc).isoformat(),
        })
        await cognee.add(applied_data, dataset_name=f"skill_{skill_name}_amendments")
        await cognee.cognify()

        result = {
            "status": "applied",
            "amendment_id": amendment_id,
            "skill_name": skill_name,
        }

        return [types.TextContent(type="text", text=json.dumps(result))]
```

- [ ] **Step 3: コミット**

```bash
git add docker/cognee-skills/skills_tools/improvements.py docker/cognee-skills/skills_tools/amend.py
git commit -m "feat(cognee-skills): add get_skill_improvements and amend_skill tools"
```

---

### Task 7: evaluate_amendment + rollback_skill ツール

**Files:**
- Create: `docker/cognee-skills/skills_tools/evaluate.py`
- Create: `docker/cognee-skills/skills_tools/rollback.py`

- [ ] **Step 1: evaluate.py を作成**

```python
"""evaluate_amendment MCP tool."""
import json
from contextlib import redirect_stdout

import sys
import mcp.types as types

from .health import calculate_health_score, needs_improvement


# Track consecutive non-improving amendments per skill
_consecutive_no_improve: dict[str, int] = {}
MAX_CONSECUTIVE_FAILURES = 3


async def evaluate_amendment_impl(
    amendment_id: str,
) -> list[types.TextContent]:
    """Evaluate whether an applied amendment improved the skill.

    Compares health scores before and after the amendment.
    If 3 consecutive amendments fail to improve, disables auto-amend for that skill.

    Args:
        amendment_id: The amendment ID to evaluate.
    """
    with redirect_stdout(sys.stderr):
        import cognee
        from cognee.api.v1.search import SearchType

        # Fetch amendment
        results = await cognee.search(
            query_type=SearchType.CHUNKS,
            query_text=f"amendment_id:{amendment_id} type:amendment",
        )

        if not results:
            return [types.TextContent(
                type="text",
                text=json.dumps({"status": "error", "message": f"Amendment {amendment_id} not found"}),
            )]

        amendment = results[0] if isinstance(results[0], dict) else json.loads(str(results[0]))
        skill_name = amendment.get("skill_name", "")
        score_before = amendment.get("score_before", 0.0)

        # Get post-amendment executions
        exec_results = await cognee.search(
            query_type=SearchType.CHUNKS,
            query_text=f"skill:{skill_name} type:execution",
            datasets=[f"skill_{skill_name}_executions"],
        )

        executions = exec_results if exec_results else []
        score_after = calculate_health_score(executions, 0)
        improved = score_after > score_before

        # Track consecutive failures for runaway prevention
        if not improved:
            count = _consecutive_no_improve.get(skill_name, 0) + 1
            _consecutive_no_improve[skill_name] = count
            if count >= MAX_CONSECUTIVE_FAILURES:
                # Disable auto-amend for this skill
                from .log_execution import _auto_amend_disabled
                _auto_amend_disabled.add(skill_name)
        else:
            _consecutive_no_improve[skill_name] = 0

        # Update amendment with evaluation
        eval_data = json.dumps({
            "type": "amendment",
            "amendment_id": amendment_id,
            "score_after": round(score_after, 3),
            "improved": improved,
        })
        await cognee.add(eval_data, dataset_name=f"skill_{skill_name}_amendments")
        await cognee.cognify()

        auto_disabled = skill_name in (
            getattr(sys.modules.get("skills_tools.log_execution", None), "_auto_amend_disabled", set())
        )

        result = {
            "status": "evaluated",
            "amendment_id": amendment_id,
            "skill_name": skill_name,
            "score_before": round(score_before, 3),
            "score_after": round(score_after, 3),
            "improved": improved,
            "recommendation": "keep" if improved else "rollback",
            "auto_amend_disabled": auto_disabled,
            "consecutive_no_improve": _consecutive_no_improve.get(skill_name, 0),
        }

        return [types.TextContent(type="text", text=json.dumps(result))]
```

- [ ] **Step 2: rollback.py を作成**

```python
"""rollback_skill MCP tool."""
import json
import os
from contextlib import redirect_stdout
from datetime import datetime, timezone

import sys
import mcp.types as types


async def rollback_skill_impl(
    amendment_id: str,
) -> list[types.TextContent]:
    """Rollback a skill to its pre-amendment version.

    Restores the skill content from the stored SkillVersion snapshot.

    Args:
        amendment_id: The amendment ID to rollback.
    """
    with redirect_stdout(sys.stderr):
        import cognee
        from cognee.api.v1.search import SearchType

        # Fetch the version snapshot created before this amendment
        version_results = await cognee.search(
            query_type=SearchType.CHUNKS,
            query_text=f"amendment_id:{amendment_id} type:skill_version",
        )

        if not version_results:
            return [types.TextContent(
                type="text",
                text=json.dumps({"status": "error", "message": f"No version snapshot found for {amendment_id}"}),
            )]

        version = version_results[0] if isinstance(version_results[0], dict) else json.loads(str(version_results[0]))
        skill_name = version.get("skill_name", "")
        original_content = version.get("content", "")
        skill_md_path = f"/skills/{skill_name}/SKILL.md"

        if not original_content:
            return [types.TextContent(
                type="text",
                text=json.dumps({"status": "error", "message": "Empty version content"}),
            )]

        # Restore original content
        try:
            with open(skill_md_path, "w") as f:
                f.write(original_content)
        except OSError as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({"status": "error", "message": f"Failed to restore: {e}"}),
            )]

        # Update amendment status
        rollback_data = json.dumps({
            "type": "amendment",
            "amendment_id": amendment_id,
            "status": "rolled_back",
            "rolled_back_at": datetime.now(timezone.utc).isoformat(),
        })
        await cognee.add(rollback_data, dataset_name=f"skill_{skill_name}_amendments")
        await cognee.cognify()

        result = {
            "status": "rolled_back",
            "amendment_id": amendment_id,
            "skill_name": skill_name,
        }

        return [types.TextContent(type="text", text=json.dumps(result))]
```

- [ ] **Step 3: コミット**

```bash
git add docker/cognee-skills/skills_tools/evaluate.py docker/cognee-skills/skills_tools/rollback.py
git commit -m "feat(cognee-skills): add evaluate_amendment and rollback_skill tools"
```

---

### Task 8: ツール登録（server.py への統合）

**Files:**
- Modify: `docker/cognee-skills/skills_tools/__init__.py`

cognee-mcp の `server.py` にカスタムツールを登録する。フォーク時に `server.py` の末尾にインポートを追加する方式。

- [ ] **Step 1: `__init__.py` にツール登録関数を作成**

```python
"""Skills tools package - registers custom MCP tools for skill improvement."""


def register_tools(mcp):
    """Register all skill improvement tools with the MCP server.

    Call this from server.py after FastMCP initialization:
        from skills_tools import register_tools
        register_tools(mcp)
    """
    from .log_execution import log_skill_execution_impl
    from .search_history import search_skill_history_impl
    from .skill_status import get_skill_status_impl
    from .improvements import get_skill_improvements_impl
    from .amend import amend_skill_impl
    from .evaluate import evaluate_amendment_impl
    from .rollback import rollback_skill_impl

    @mcp.tool(name="log_skill_execution", description="Log a skill execution result for tracking and improvement analysis.")
    async def log_skill_execution(skill_name: str, agent: str, task_description: str, success: bool, error: str = None, duration_ms: int = None):
        return await log_skill_execution_impl(skill_name, agent, task_description, success, error, duration_ms)

    @mcp.tool(name="search_skill_history", description="Search past skill execution history with optional filters.")
    async def search_skill_history(skill_name: str = None, agent: str = None, success: bool = None, limit: int = 20):
        return await search_skill_history_impl(skill_name, agent, success, limit)

    @mcp.tool(name="get_skill_status", description="Get the health status summary of a skill including success rate and failure patterns.")
    async def get_skill_status(skill_name: str):
        return await get_skill_status_impl(skill_name)

    @mcp.tool(name="get_skill_improvements", description="Generate improvement proposals for a skill based on failure patterns.")
    async def get_skill_improvements(skill_name: str, min_executions: int = 5):
        return await get_skill_improvements_impl(skill_name, min_executions)

    @mcp.tool(name="amend_skill", description="Apply a proposed skill amendment to the skill directory.")
    async def amend_skill(amendment_id: str):
        return await amend_skill_impl(amendment_id)

    @mcp.tool(name="evaluate_amendment", description="Evaluate whether an applied amendment improved the skill by comparing health scores.")
    async def evaluate_amendment(amendment_id: str):
        return await evaluate_amendment_impl(amendment_id)

    @mcp.tool(name="rollback_skill", description="Rollback a skill to its pre-amendment version if the amendment did not improve it.")
    async def rollback_skill(amendment_id: str):
        return await rollback_skill_impl(amendment_id)
```

- [ ] **Step 2: server.py にツール登録を追加**

cognee-mcp フォークの `cognee-mcp/src/server.py` を編集。`mcp = FastMCP("Cognee")` 行（ファイル先頭付近のグローバルスコープ）の直後に以下を追加:

```python
# Register custom skill improvement tools
from skills_tools import register_tools
register_tools(mcp)
```

Note: Dockerfile の `COPY skills_tools/ /app/cognee/cognee-mcp/src/skills_tools/` によって、`skills_tools` パッケージは `src/` 配下にコピーされるため、`server.py` から相対インポートできる。

- [ ] **Step 3: リビルドして全ツールが登録されていることを確認**

```bash
cd docker/cognee-skills
docker compose up -d --build cognee-mcp-skills
# MCP ツール一覧の確認（HTTP endpoint）
curl -X POST http://localhost:8000/mcp -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

Expected: レスポンスに `log_skill_execution`, `search_skill_history`, `get_skill_status`, `get_skill_improvements`, `amend_skill`, `evaluate_amendment`, `rollback_skill` が含まれる

- [ ] **Step 4: コミット**

```bash
git add docker/cognee-skills/skills_tools/__init__.py
git commit -m "feat(cognee-skills): register all custom tools with MCP server"
```

---

### Task 9: エージェント統合（MCP 設定 + OpenClaw ネットワーク）

**Files:**
- Modify: `chezmoi/.chezmoidata/mcp_servers.yaml`
- Modify: `chezmoi/dot_openclaw/openclaw.docker.json.tmpl`
- Modify: `docker/openclaw/docker-compose.yml`

- [ ] **Step 1: mcp_servers.yaml に cognee-skills を追加**

ファイル `chezmoi/.chezmoidata/mcp_servers.yaml` の `mcp_servers:` リストの末尾に追加:

```yaml
  - name: cognee-skills
    url: "http://localhost:8000/mcp"
    supports:
      - codex
      - claude
      - cursor
      - gemini
```

- [ ] **Step 2: openclaw.docker.json.tmpl に MCP サーバー追加**

`chezmoi/dot_openclaw/openclaw.docker.json.tmpl` の `mcpServers` セクション（存在しない場合は適切な位置に追加）:

```json
"cognee-skills": {
  "type": "url",
  "url": "http://cognee-mcp-skills:8000/mcp"
}
```

- [ ] **Step 3: OpenClaw docker-compose.yml に cognee-network 追加**

`docker/openclaw/docker-compose.yml` に以下を追加:

サービスの `openclaw` に `networks` を追加:
```yaml
    networks:
      - default
      - cognee-network
```

トップレベルに `networks` を追加:
```yaml
networks:
  default:
  cognee-network:
    external: true
```

- [ ] **Step 4: chezmoi apply で設定を反映し確認**

```bash
chezmoi apply
```

- [ ] **Step 5: コミット**

```bash
git add chezmoi/.chezmoidata/mcp_servers.yaml chezmoi/dot_openclaw/openclaw.docker.json.tmpl docker/openclaw/docker-compose.yml
git commit -m "feat(cognee-skills): integrate MCP server with all agents + OpenClaw network"
```

---

### Task 10: PowerShell ハンドラー

**Files:**
- Create: `scripts/powershell/handlers/Handler.CogneeSkills.ps1`
- Reference: `scripts/powershell/handlers/Handler.OpenClaw.ps1`（パターン参照）

- [ ] **Step 1: Handler.CogneeSkills.ps1 を作成**

OpenClaw ハンドラーの2層ゲートパターンに倣い、cognee-skills コンテナの管理ハンドラーを作成。

```powershell
class CogneeSkillsHandler : SetupHandlerBase {
    [string]$Name = "CogneeSkills"
    [string]$Description = "cognee-skills MCP server (self-improving skills)"
    [int]$Order = 130  # After OpenClaw (120)

    hidden [string] GetComposeDir([SetupContext]$ctx) {
        return Join-Path $ctx.DotfilesPath "docker/cognee-skills"
    }

    hidden [string] GetSecretDir() {
        return Join-Path $HOME ".openclaw/secrets"
    }

    hidden [nullable[bool]] ReadCogneeSkillsEnabled() {
        $chezmoiToml = Join-Path $HOME ".config/chezmoi/chezmoi.toml"
        if (-not (Test-PathExist -Path $chezmoiToml)) { return $null }
        $content = Get-Content $chezmoiToml -Raw
        if ($content -match 'cognee_skills_enabled\s*=\s*(true|false)') {
            return [bool]::Parse($Matches[1])
        }
        return $null
    }

    hidden [void] WriteCogneeSkillsEnabled([bool]$enabled) {
        $chezmoiToml = Join-Path $HOME ".config/chezmoi/chezmoi.toml"
        $value = if ($enabled) { "true" } else { "false" }
        if (Test-PathExist -Path $chezmoiToml) {
            $content = Get-Content $chezmoiToml -Raw
            if ($content -match 'cognee_skills_enabled\s*=') {
                $content = $content -replace 'cognee_skills_enabled\s*=\s*(true|false)', "cognee_skills_enabled = $value"
            } else {
                $content = $content.TrimEnd() + "`ncognee_skills_enabled = $value`n"
            }
            Set-ContentNoNewline -Path $chezmoiToml -Value $content
        }
    }

    [bool] CanApply([SetupContext]$ctx) {
        # Layer 1: Interaction gate
        $enabled = $this.ReadCogneeSkillsEnabled()
        if ($null -eq $enabled) {
            if (-not (Test-InteractiveEnvironment)) {
                $this.Log("非対話環境のためスキップします", "Yellow")
                return $false
            }
            Write-Host "  cognee-skills (自己改善スキル MCP サーバー) を検出しました。" -ForegroundColor Yellow
            Write-Host "  セットアップしますか？" -ForegroundColor Yellow
            $answer = Read-Host "  [y/N]"
            $enabled = ($answer -match '^[yY]')
            $this.WriteCogneeSkillsEnabled($enabled)
            if (-not $enabled) { return $false }
        } elseif (-not $enabled) {
            $this.Log("cognee-skills は無効です (chezmoi.toml)", "Gray")
            return $false
        }

        # Layer 2: Infrastructure gate
        $composeDir = $this.GetComposeDir($ctx)
        $composeFile = Join-Path $composeDir "docker-compose.yml"

        if (-not (Test-PathExist -Path $composeFile)) {
            $this.LogWarning("docker-compose.yml が見つかりません: $composeFile")
            return $false
        }

        $dockerCmd = Get-ExternalCommand -Name "docker"
        if (-not $dockerCmd) {
            $this.LogWarning("docker コマンドが見つかりません")
            return $false
        }

        return $true
    }

    [SetupResult] Apply([SetupContext]$ctx) {
        $composeDir = $this.GetComposeDir($ctx)
        $composeFile = Join-Path $composeDir "docker-compose.yml"
        $envFile = Join-Path $composeDir ".env"

        try {
            # Ensure .env exists
            $this.EnsureEnvFile($ctx)

            # Create cognee-network if it doesn't exist
            try {
                Invoke-Docker "network" "create" "cognee-network" 2>$null
            } catch {
                # Network already exists, ignore
            }

            # Build and start
            $this.Log("cognee-skills コンテナをビルド・起動します...", "Cyan")
            Invoke-Docker "compose" "-f" ($composeFile -replace '\\', '/') "up" "-d" "--build"

            if ($LASTEXITCODE -ne 0) {
                return $this.CreateFailureResult("docker compose up に失敗しました")
            }

            # Wait for health check
            $this.Log("ヘルスチェックを待機中...", "Gray")
            $healthy = $this.WaitForContainer($composeFile)

            if ($healthy) {
                return $this.CreateSuccessResult("cognee-skills MCP サーバーが起動しました (http://localhost:8000/mcp)")
            } else {
                return $this.CreateFailureResult("ヘルスチェックがタイムアウトしました")
            }
        } catch {
            return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
        }
    }

    hidden [void] EnsureEnvFile([SetupContext]$ctx) {
        $composeDir = $this.GetComposeDir($ctx)
        $envFile = Join-Path $composeDir ".env"

        if (Test-PathExist -Path $envFile) {
            $this.Log(".env ファイルが存在します", "Gray")
            return
        }

        $secretDir = ($this.GetSecretDir() -replace '\\', '/')
        $skillsPath = (Join-Path $ctx.DotfilesPath "chezmoi/dot_claude/skills" -replace '\\', '/')

        $envContent = @"
LLM_PROVIDER=gemini
EMBEDDING_PROVIDER=gemini
EMBEDDING_MODEL=gemini-embedding-2-preview
SKILLS_PATH=$skillsPath
OPENCLAW_GEMINI_API_KEY_FILE=$secretDir/gemini_api_key
SKILL_HEALTH_WINDOW=20
SKILL_HEALTH_THRESHOLD=0.7
SKILL_CORRECTION_PENALTY=0.05
"@

        Set-ContentNoNewline -Path $envFile -Value $envContent
        $this.Log(".env ファイルを作成しました", "Green")
    }

    hidden [bool] WaitForContainer([string]$composeFile, [int]$maxRetries = 12, [int]$delaySeconds = 5) {
        for ($i = 1; $i -le $maxRetries; $i++) {
            try {
                $health = Invoke-Docker "compose" "-f" ($composeFile -replace '\\', '/') "ps" "--format" "json" 2>$null
                if ($health -match '"healthy"') {
                    return $true
                }
            } catch { }
            Start-SleepSafe -Seconds $delaySeconds
        }
        return $false
    }
}
```

- [ ] **Step 2: コミット**

```bash
git add scripts/powershell/handlers/Handler.CogneeSkills.ps1
git commit -m "feat(cognee-skills): add PowerShell handler for container lifecycle management"
```

---

### Task 11: 統合テスト

- [ ] **Step 1: 全コンテナ起動**

```bash
cd docker/cognee-skills
docker compose up -d --build
```

- [ ] **Step 2: ヘルスチェック確認**

```bash
curl http://localhost:8000/health
```

Expected: `{"status": "ok"}`

- [ ] **Step 3: ツール一覧確認**

```bash
curl -X POST http://localhost:8000/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

Expected: 7つのカスタムツール + 公式ツールが一覧に表示

- [ ] **Step 4: log_skill_execution を手動実行**

```bash
curl -X POST http://localhost:8000/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc":"2.0","id":2,"method":"tools/call",
    "params":{
      "name":"log_skill_execution",
      "arguments":{
        "skill_name":"dockerfile-optimization",
        "agent":"claude-code",
        "task_description":"test execution",
        "success":true
      }
    }
  }'
```

Expected: `{"status":"logged","execution_id":"...","skill_name":"dockerfile-optimization","success":true}`

- [ ] **Step 5: get_skill_status を確認**

```bash
curl -X POST http://localhost:8000/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc":"2.0","id":3,"method":"tools/call",
    "params":{
      "name":"get_skill_status",
      "arguments":{"skill_name":"dockerfile-optimization"}
    }
  }'
```

Expected: `{"skill_name":"dockerfile-optimization","health_score":1.0,...}`

- [ ] **Step 6: OpenClaw ネットワーク接続確認**

```bash
# cognee-network が存在することを確認
docker network inspect cognee-network

# OpenClaw コンテナから cognee-mcp-skills に到達できることを確認（OpenClaw が起動している場合）
docker exec openclaw curl -sf http://cognee-mcp-skills:8000/health
```

- [ ] **Step 7: コミット（全タスク完了）**

```bash
git add -A
git commit -m "feat(cognee-skills): complete integration testing and final adjustments"
```
