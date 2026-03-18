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

        limited = results[:limit] if results else []

        return [types.TextContent(type="text", text=json.dumps(limited, default=str))]
