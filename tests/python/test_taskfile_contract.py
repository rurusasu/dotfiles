"""Taskfile contracts for Hermes X MCP lifecycle operations."""

from __future__ import annotations

import unittest
from pathlib import Path

import yaml


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
TASKFILE = REPOSITORY_ROOT / "Taskfile.yml"


class TaskfileContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tasks = yaml.safe_load(TASKFILE.read_text(encoding="utf-8"))["tasks"]

    def test_xapi_tasks_are_present_in_the_hermes_lifecycle(self) -> None:
        self.assertIn("xapi-mcp", self._command_text("hermes:pull"))
        self.assertIn(
            "xurl auth oauth2 --headless",
            self._command_text("hermes:xapi:auth"),
        )
        self.assertIn(
            "up -d --force-recreate xapi-mcp",
            self._command_text("hermes:xapi:restart"),
        )
        self.assertIn(
            "logs -f --tail=100 xapi-mcp",
            self._command_text("hermes:xapi:logs"),
        )

    def _command_text(self, task_name: str) -> str:
        task = self.tasks[task_name]
        commands = task.get("cmds", [])
        return "\n".join(
            command if isinstance(command, str) else command.get("cmd", "")
            for command in commands
        )


if __name__ == "__main__":
    unittest.main()
