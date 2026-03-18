"""get_skill_improvements MCP tool."""
import json
import os
from contextlib import redirect_stdout
from datetime import datetime, timezone
from uuid import uuid4

import sys
import mcp.types as types

from .health import calculate_health_score


async def get_skill_improvements_impl(
    skill_name: str,
    min_executions: int = 5,
) -> list[types.TextContent]:
    """Generate improvement proposals based on execution history.

    Args:
        skill_name: Name of the skill to improve.
        min_executions: Minimum executions required before proposing improvements.
    """
    with redirect_stdout(sys.stderr):
        import cognee
        from cognee.api.v1.search import SearchType

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

        skill_dir = f"/skills/{skill_name}"
        skill_md_path = f"{skill_dir}/SKILL.md"

        if not os.path.exists(skill_md_path):
            return [types.TextContent(
                type="text",
                text=json.dumps({"status": "error", "message": f"SKILL.md not found at {skill_md_path}"}),
            )]

        with open(skill_md_path) as f:
            current_content = f.read()

        failures = [e for e in executions if not e.get("success", True)]
        failure_summary = "\n".join(
            f"- Error: {f.get('error', 'unknown')} (agent: {f.get('agent', '?')}, task: {f.get('task_description', '?')})"
            for f in failures[-10:]
        )

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
