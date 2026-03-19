"""evaluate_amendment MCP tool."""
import json
from contextlib import redirect_stdout

import sys
import mcp.types as types

from .health import calculate_health_score

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

        exec_results = await cognee.search(
            query_type=SearchType.CHUNKS,
            query_text=f"skill:{skill_name} type:execution",
            datasets=[f"skill_{skill_name}_executions"],
        )

        executions = exec_results if exec_results else []
        score_after = calculate_health_score(executions, 0)
        improved = score_after > score_before

        if not improved:
            count = _consecutive_no_improve.get(skill_name, 0) + 1
            _consecutive_no_improve[skill_name] = count
            if count >= MAX_CONSECUTIVE_FAILURES:
                from .log_execution import _auto_amend_disabled
                _auto_amend_disabled.add(skill_name)
        else:
            _consecutive_no_improve[skill_name] = 0

        eval_data = json.dumps({
            "type": "amendment",
            "amendment_id": amendment_id,
            "score_after": round(score_after, 3),
            "improved": improved,
        })
        await cognee.add(eval_data, dataset_name=f"skill_{skill_name}_amendments")
        await cognee.cognify()

        from .log_execution import _auto_amend_disabled
        auto_disabled = skill_name in _auto_amend_disabled

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
