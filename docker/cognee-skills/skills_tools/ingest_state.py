"""SQLite-based state management for session ingestion deduplication."""

import sqlite3
from datetime import datetime, timezone
from pathlib import Path

DB_PATH = Path("/app/data/cognee-ingest-state.db")


def _connect() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(DB_PATH))
    conn.execute(
        """CREATE TABLE IF NOT EXISTS ingested_sessions (
            session_id TEXT PRIMARY KEY,
            agent_id TEXT NOT NULL,
            ingested_at TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            retry_count INTEGER NOT NULL DEFAULT 0
        )"""
    )
    conn.commit()
    return conn


def is_ingested(session_id: str) -> bool:
    conn = _connect()
    try:
        row = conn.execute(
            "SELECT status FROM ingested_sessions WHERE session_id = ?",
            (session_id,),
        ).fetchone()
        return row is not None and row[0] == "ingested"
    finally:
        conn.close()


def should_retry(session_id: str) -> bool:
    conn = _connect()
    try:
        row = conn.execute(
            "SELECT status, retry_count FROM ingested_sessions WHERE session_id = ?",
            (session_id,),
        ).fetchone()
        if row is None:
            return True
        status, retry_count = row
        return status == "failed" and retry_count < 3
    finally:
        conn.close()


def mark_ingested(session_id: str, agent_id: str) -> None:
    now = datetime.now(timezone.utc).isoformat()
    conn = _connect()
    try:
        conn.execute(
            """INSERT INTO ingested_sessions (session_id, agent_id, ingested_at, status)
               VALUES (?, ?, ?, 'ingested')
               ON CONFLICT(session_id) DO UPDATE SET
                 status = 'ingested', ingested_at = excluded.ingested_at""",
            (session_id, agent_id, now),
        )
        conn.commit()
    finally:
        conn.close()


def mark_failed(session_id: str, agent_id: str) -> None:
    now = datetime.now(timezone.utc).isoformat()
    conn = _connect()
    try:
        conn.execute(
            """INSERT INTO ingested_sessions (session_id, agent_id, ingested_at, status, retry_count)
               VALUES (?, ?, ?, 'failed', 1)
               ON CONFLICT(session_id) DO UPDATE SET
                 status = 'failed',
                 retry_count = retry_count + 1,
                 ingested_at = excluded.ingested_at""",
            (session_id, agent_id, now),
        )
        # Auto-abandon after 3 failures
        conn.execute(
            """UPDATE ingested_sessions
               SET status = 'abandoned'
               WHERE session_id = ? AND retry_count >= 3""",
            (session_id,),
        )
        conn.commit()
    finally:
        conn.close()
