"""Deny direct git commits on protected branches (main, staging, master).

Shared PreToolUse hook for Claude Code (.claude/settings.json) and
Codex CLI (.codex/config.toml). Both pass the same JSON payload on stdin.
"""

from __future__ import annotations

import json
import os
import shlex
import subprocess
import sys
from typing import Any

PROTECTED_BRANCHES = {"main", "staging", "master"}

# Global git options that consume the following token as their argument.
GIT_OPTS_WITH_ARG = {
    "-c",
    "-C",
    "--git-dir",
    "--work-tree",
    "--namespace",
    "--exec-path",
    "--config-env",
}


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


def tokenize(segment: str) -> list[str]:
    """Tokenize shell-aware so quoted values (e.g. -c user.name="Jane Doe")
    stay single tokens. Fall back to naive splitting on unbalanced quotes."""
    try:
        return shlex.split(segment, posix=True)
    except ValueError:
        return segment.split()


def parse_git_segment(segment: str) -> tuple[str | None, list[str]]:
    """Return (subcommand, global option tokens) for a git invocation.

    Global options such as -C/--git-dir/--work-tree change which repository
    the subcommand operates on, so they are collected for branch resolution.
    """
    tokens = tokenize(segment)
    if not tokens:
        return None, []

    program = os.path.basename(tokens[0]).lower()
    if program not in {"git", "git.exe"}:
        return None, []

    global_opts: list[str] = []
    i = 1
    while i < len(tokens):
        token = tokens[i]
        if token in GIT_OPTS_WITH_ARG:
            global_opts.extend(tokens[i : i + 2])
            i += 2
            continue
        if token.startswith("-"):
            global_opts.append(token)
            i += 1
            continue
        return token, global_opts
    return None, global_opts


def current_branch(cwd: str | None, global_opts: list[str]) -> str | None:
    """Resolve the branch of the repository the git invocation targets.

    Re-passing the global options (e.g. -C <path>) makes git itself resolve
    the effective working tree, matching the commit invocation exactly.
    """
    try:
        result = subprocess.run(
            ["git", *global_opts, "branch", "--show-current"],
            cwd=cwd or None,
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0:
        return None
    return result.stdout.strip() or None


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
        subcommand, global_opts = parse_git_segment(segment)
        if subcommand != "commit":
            continue
        branch = current_branch(payload.get("cwd"), global_opts)
        if branch in PROTECTED_BRANCHES:
            deny(
                f"Direct commits to protected branch '{branch}' are prohibited. "
                "Create a feature branch and open a PR instead."
            )
            break

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
