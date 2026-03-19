"""amend_skill MCP tool."""
import hashlib
import json
import os
from contextlib import redirect_stdout
from datetime import datetime, timezone

import sys
import mcp.types as types


async def amend_skill_impl(
    amendment_id: str,
) -> list[types.TextContent]:
    """Apply a proposed skill amendment.

    Args:
        amendment_id: The amendment ID to apply.
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
        skill_dir = f"/skills/{skill_name}"
        skill_md_path = f"{skill_dir}/SKILL.md"

        if not os.path.exists(skill_md_path):
            return [types.TextContent(
                type="text",
                text=json.dumps({"status": "error", "message": f"Skill directory not found: {skill_dir}"}),
            )]

        with open(skill_md_path) as f:
            original_content = f.read()

        version_data = json.dumps({
            "type": "skill_version",
            "skill_name": skill_name,
            "content": original_content,
            "content_hash": hashlib.sha256(original_content.encode()).hexdigest(),
            "created_at": datetime.now(timezone.utc).isoformat(),
            "amendment_id": amendment_id,
        })

        await cognee.add(version_data, dataset_name=f"skill_{skill_name}_versions")

        proposal = amendment.get("proposal", "")

        try:
            if isinstance(proposal, str) and proposal.strip():
                with open(skill_md_path, "w") as f:
                    f.write(proposal)
            else:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({"status": "error", "message": "Empty proposal content"}),
                )]
        except OSError as e:
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
