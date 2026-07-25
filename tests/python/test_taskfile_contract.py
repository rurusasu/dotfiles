"""Taskfile contracts for Hermes X MCP lifecycle operations."""

from __future__ import annotations

import unittest
from pathlib import Path

import yaml


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
TASKFILE = REPOSITORY_ROOT / "Taskfile.yml"
HERMES_AGENT = REPOSITORY_ROOT / "scripts" / "sh" / "hermes-agent.sh"
XAPI_WRAPPER = REPOSITORY_ROOT / "scripts" / "sh" / "hermes-xapi.sh"
XAPI_WINDOWS_WRAPPER = REPOSITORY_ROOT / "scripts" / "powershell" / "hermes-xapi.ps1"


class TaskfileContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tasks = yaml.safe_load(TASKFILE.read_text(encoding="utf-8"))["tasks"]

    def test_xapi_tasks_are_present_in_the_hermes_lifecycle(self) -> None:
        self.assertIn("xapi-mcp", self._command_text("hermes:pull"))
        self.assertIn(
            "scripts/sh/hermes-xapi.sh auth",
            self._command_text("hermes:xapi:auth"),
        )
        self.assertIn(
            "scripts/powershell/hermes-xapi.ps1 -Action auth",
            self._command_text("hermes:xapi:auth"),
        )
        self.assertIn(
            "scripts/sh/hermes-xapi.sh restart",
            self._command_text("hermes:xapi:restart"),
        )
        self.assertIn(
            "scripts/powershell/hermes-xapi.ps1 -Action restart",
            self._command_text("hermes:xapi:restart"),
        )
        self.assertIn(
            "scripts/sh/hermes-xapi.sh up",
            self._command_text("hermes:up"),
        )
        self.assertIn(
            "scripts/powershell/hermes-xapi.ps1 -Action up",
            self._command_text("hermes:up"),
        )
        self.assertIn(
            "logs -f --tail=100 xapi-mcp",
            self._command_text("hermes:xapi:logs"),
        )

    def test_bootstrap_uses_the_same_container_startup_guardrails(self) -> None:
        task = self.tasks["hermes:bootstrap"]
        precondition_text = "\n".join(
            precondition.get("sh", "") for precondition in task.get("preconditions", [])
        )

        self.assertIs(task.get("interactive"), True)
        self.assertIn("docker info", precondition_text)
        self.assertIn("test -f {{.HERMES_COMPOSE_FILE}}", precondition_text)
        self.assertIn(
            'dotfiles_hermes_start_stack docker "{{.HERMES_COMPOSE_FILE}}"',
            self._command_text("hermes:bootstrap"),
        )

    def test_xapi_lifecycle_reads_oauth_credentials_from_1password(self) -> None:
        wrapper = XAPI_WRAPPER.read_text(encoding="utf-8")
        windows_wrapper = XAPI_WINDOWS_WRAPPER.read_text(encoding="utf-8")
        adapter = HERMES_AGENT.read_text(encoding="utf-8")

        self.assertIn("dotfiles_hermes_with_xapi_credentials", wrapper)
        self.assertIn("xurl auth oauth2 --headless", wrapper)
        self.assertIn("up -d --force-recreate xapi-mcp", wrapper)
        self.assertIn("up -d --force-recreate", wrapper)
        self.assertIn("Invoke-HermesXApiCredentialScope", windows_wrapper)
        self.assertIn("xurl auth oauth2 --headless", windows_wrapper)
        self.assertIn("'up', '-d', '--force-recreate', 'xapi-mcp'", windows_wrapper)
        self.assertIn("'up', '-d', '--force-recreate'", windows_wrapper)
        self.assertIn("X_API_CLIENT_ID", windows_wrapper)
        self.assertIn("X_API_CLIENT_SECRET", windows_wrapper)

        self.assertIn("Hermes X API MCP", adapter)
        self.assertIn("X_API_CLIENT_ID", adapter)
        self.assertIn("X_API_CLIENT_SECRET", adapter)
        self.assertIn('signin --account "$account"', adapter)
        self.assertIn('item get "$item"', adapter)
        self.assertIn("jq -e -c", adapter)
        self.assertNotIn("jq -erce", adapter)
        self.assertNotIn("X_API_CLIENT_SECRET='", wrapper)

    def _command_text(self, task_name: str) -> str:
        task = self.tasks[task_name]
        commands = task.get("cmds", [])
        return "\n".join(
            command if isinstance(command, str) else command.get("cmd", "")
            for command in commands
        )


if __name__ == "__main__":
    unittest.main()
