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

    Args:
        amendment_id: The amendment ID to rollback.
    """
    with redirect_stdout(sys.stderr):
        import cognee
        from cognee.api.v1.search import SearchType

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

        try:
            with open(skill_md_path, "w") as f:
                f.write(original_content)
        except OSError as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({"status": "error", "message": f"Failed to restore: {e}"}),
            )]

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
