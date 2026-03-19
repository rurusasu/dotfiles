"""get_skill_status MCP tool."""
import json
from contextlib import redirect_stdout

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

        exec_results = await cognee.search(
            query_type=SearchType.CHUNKS,
            query_text=f"skill:{skill_name} type:execution",
            datasets=[f"skill_{skill_name}_executions"],
        )

        executions = exec_results if exec_results else []

        feedback_results = await cognee.search(
            query_type=SearchType.CHUNKS,
            query_text=f"skill:{skill_name} type:feedback feedback_type:user_correction",
        )
        correction_count = len(feedback_results) if feedback_results else 0

        score = calculate_health_score(executions, correction_count)

        failures = [e for e in executions if not e.get("success", True)]
        error_messages = [f.get("error", "unknown") for f in failures[-5:]]

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
