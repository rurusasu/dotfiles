"""ingest_transcript MCP tool — add session JSONL to Cognee knowledge graph."""

import json
import sys
from contextlib import redirect_stdout
from pathlib import Path

import mcp.types as types

from .ingest_state import is_ingested, mark_failed, mark_ingested, should_retry

MAX_FILE_SIZE = 10 * 1024 * 1024  # 10 MB
CHUNK_SIZE = 5 * 1024 * 1024  # 5 MB per chunk


async def ingest_transcript_impl(
    agent_id: str,
    session_id: str,
    file_path: str,
) -> list[types.TextContent]:
    """Read a session JSONL file and add it to Cognee for knowledge extraction.

    Deduplication is handled internally via SQLite state DB.
    Already-ingested sessions are skipped. Failed sessions are retried up to 3 times.

    Args:
        agent_id: Agent ID (e.g. "main", "slack-C0AK3SQKFV2").
        session_id: Session ID for deduplication.
        file_path: Path to the JSONL file inside the Cognee container
                   (e.g. "/openclaw-sessions/sessions/xxx.jsonl").
    """
    with redirect_stdout(sys.stderr):
        # Dedup check
        if is_ingested(session_id):
            return [types.TextContent(
                type="text",
                text=json.dumps({"status": "skipped", "reason": "already ingested", "session_id": session_id}),
            )]

        if not should_retry(session_id):
            return [types.TextContent(
                type="text",
                text=json.dumps({"status": "skipped", "reason": "abandoned after 3 failures", "session_id": session_id}),
            )]

        path = Path(file_path)
        if not path.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({"status": "error", "error": f"File not found: {file_path}"}),
            )]

        file_size = path.stat().st_size
        if file_size == 0:
            return [types.TextContent(
                type="text",
                text=json.dumps({"status": "skipped", "reason": "empty file"}),
            )]

        try:
            import cognee

            content = path.read_text(encoding="utf-8")
            dataset_name = f"sessions_{agent_id}"
            chunks_added = 0

            if file_size <= MAX_FILE_SIZE:
                await cognee.add(content, dataset_name=dataset_name)
                chunks_added = 1
            else:
                # Split into chunks for large files
                lines = content.splitlines(keepends=True)
                chunk = []
                chunk_size = 0
                for line in lines:
                    chunk.append(line)
                    chunk_size += len(line.encode("utf-8"))
                    if chunk_size >= CHUNK_SIZE:
                        await cognee.add("".join(chunk), dataset_name=dataset_name)
                        chunks_added += 1
                        chunk = []
                        chunk_size = 0
                if chunk:
                    await cognee.add("".join(chunk), dataset_name=dataset_name)
                    chunks_added += 1

            mark_ingested(session_id, agent_id)
            result = {
                "status": "ok",
                "chunks_added": chunks_added,
                "agent_id": agent_id,
                "session_id": session_id,
                "file_size_bytes": file_size,
            }
        except Exception as e:
            mark_failed(session_id, agent_id)
            result = {
                "status": "error",
                "error": str(e),
                "agent_id": agent_id,
                "session_id": session_id,
            }

        return [types.TextContent(type="text", text=json.dumps(result))]
