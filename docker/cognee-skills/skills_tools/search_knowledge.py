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
