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

            await cognee.add(
                json.dumps(execution.model_dump(), default=str),
                dataset_name=f"skill_{skill_name}_executions",
            )
            await cognee.cognify()

            # Auto-improvement trigger
            if skill_name not in _auto_amend_disabled:
                exec_results = await cognee.search(
                    query_type="CHUNKS",
                    query_text=f"skill_id:{skill_name}",
                    datasets=[f"skill_{skill_name}_executions"],
                )
                executions_list = exec_results or []
                score = calculate_health_score(executions_list, 0)

                if needs_improvement(score):
                    last = _last_amendment.get(skill_name)
                    if last and (now - last).total_seconds() < 86400:
                        pass
                    else:
                        from .improvements import get_skill_improvements_impl
                        asyncio.create_task(
                            get_skill_improvements_impl(skill_name, min_executions=5)
                        )
                        _last_amendment[skill_name] = now

        except Exception as e:
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
