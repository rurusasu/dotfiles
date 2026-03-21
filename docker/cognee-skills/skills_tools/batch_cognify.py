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
