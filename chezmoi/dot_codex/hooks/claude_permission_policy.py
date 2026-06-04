"""Claude-aligned command policy hook for Codex."""

from __future__ import annotations

import json
import re
import sys
from typing import Any


PYTHON_PREFIX_RE = re.compile(r"(?is)^\s*(?:python|python3)(?:\s|$)")


def deny(reason: str) -> None:
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": reason,
                }
            },
            separators=(",", ":"),
        )
    )


def split_shell_segments(command: str) -> list[str]:
    segments: list[str] = []
    buf: list[str] = []
    quote: str | None = None
    i = 0

    while i < len(command):
        ch = command[i]

        if quote is not None:
            buf.append(ch)
            if ch == "\\" and quote == '"' and i + 1 < len(command):
                i += 1
                buf.append(command[i])
            elif ch == quote:
                quote = None
            i += 1
            continue

        if ch in {"'", '"'}:
            quote = ch
            buf.append(ch)
            i += 1
            continue

        if command.startswith("&&", i) or command.startswith("||", i):
            segment = "".join(buf).strip()
            if segment:
                segments.append(segment)
            buf = []
            i += 2
            continue

        if ch in {";", "|"}:
            segment = "".join(buf).strip()
            if segment:
                segments.append(segment)
            buf = []
            i += 1
            continue

        buf.append(ch)
        i += 1

    segment = "".join(buf).strip()
    if segment:
        segments.append(segment)
    return segments


def main() -> int:
    try:
        payload: dict[str, Any] = json.load(sys.stdin)
    except json.JSONDecodeError:
        return 0

    if payload.get("hook_event_name") != "PreToolUse":
        return 0
    if payload.get("tool_name") != "Bash":
        return 0

    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        return 0

    command = tool_input.get("command")
    if not isinstance(command, str):
        return 0

    for segment in split_shell_segments(command):
        if PYTHON_PREFIX_RE.search(segment) and "pyproject" in segment.lower():
            deny(
                "Blocked to match Claude permissions: Python commands that reference pyproject are denied."
            )
            break

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
