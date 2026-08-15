"""Taskfile contracts for Hermes lifecycle operations."""

from __future__ import annotations

import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
TASKFILE = REPOSITORY_ROOT / "Taskfile.yml"
HERMES_AGENT = REPOSITORY_ROOT / "scripts" / "sh" / "hermes-agent.sh"
XAPI_WRAPPER = REPOSITORY_ROOT / "scripts" / "sh" / "hermes-xapi.sh"
XAPI_WINDOWS_WRAPPER = REPOSITORY_ROOT / "scripts" / "powershell" / "hermes-xapi.ps1"
HINDSIGHT_WRAPPER = REPOSITORY_ROOT / "scripts" / "sh" / "hermes-hindsight-verify.sh"
HINDSIGHT_WINDOWS_WRAPPER = (
    REPOSITORY_ROOT / "scripts" / "powershell" / "hermes-hindsight-verify.ps1"
)
HERMES_DOCKERFILE = REPOSITORY_ROOT / "docker" / "hermes-agent" / "Dockerfile"
HINDSIGHT_ACCEPTANCE = (
    REPOSITORY_ROOT / "docker" / "hermes-agent" / "hindsight_acceptance.py"
)


class TaskfileContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.taskfile = TASKFILE.read_text(encoding="utf-8")

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
        task = self._task_block("hermes:bootstrap")

        self.assertIn("interactive: true", task)
        self.assertIn("docker info", task)
        self.assertIn("test -f {{.HERMES_COMPOSE_FILE}}", task)
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

    def test_hindsight_acceptance_task_delegates_to_both_platform_entrypoints(
        self,
    ) -> None:
        task = self._task_block("hermes:memory:verify")

        self.assertIn("scripts/sh/hermes-hindsight-verify.sh", task)
        self.assertIn("platforms: [linux, darwin]", task)
        self.assertIn(
            "pwsh -NoProfile -File scripts/powershell/hermes-hindsight-verify.ps1",
            task,
        )
        self.assertIn("platforms: [windows]", task)
        self.assertNotIn("hermes-hindsight-acceptance", task)

    def test_hindsight_acceptance_wrappers_require_the_same_eleven_phases(self) -> None:
        unix = HINDSIGHT_WRAPPER.read_text(encoding="utf-8")
        windows = HINDSIGHT_WINDOWS_WRAPPER.read_text(encoding="utf-8")

        unix_phases = (
            "config --quiet",
            "dotfiles_hermes_hindsight_prepare_host",
            "dotfiles_hermes_hindsight_start",
            "hermes-hindsight-acceptance probe",
            "hermes-hindsight-acceptance seed",
            "restart hindsight",
            "hermes-hindsight-acceptance verify",
            "stop hindsight",
            "hermes-hindsight-acceptance degraded",
            "start hindsight",
            "hermes-hindsight-acceptance cleanup",
        )
        windows_phases = (
            "'config', '--quiet'",
            "Initialize-HermesHindsightHost",
            "'up', '-d', 'hindsight'",
            "'hermes-hindsight-acceptance', 'probe'",
            "'hermes-hindsight-acceptance', 'seed'",
            "'restart', 'hindsight'",
            "'hermes-hindsight-acceptance', 'verify'",
            "'stop', 'hindsight'",
            "'hermes-hindsight-acceptance', 'degraded'",
            "'start', 'hindsight'",
            "'hermes-hindsight-acceptance', 'cleanup'",
        )
        self._assert_in_order(unix, unix_phases)
        self._assert_in_order(windows, windows_phases)

        profiles = "default,rick,hoffman,risarisa,nancy,kuroda,shiraishi"
        normalized_unix = " ".join(unix.split())
        for wrapper in (unix, windows):
            self.assertIn(profiles, wrapper)
            self.assertIn("HERMES_ALIVE", wrapper)
            self.assertNotIn("--skip", wrapper.lower())
            self.assertNotIn("|| true", wrapper)
            self.assertNotIn("--profile default", wrapper)
            self.assertNotIn("--profiles default\n", wrapper)
        self.assertIn("--strict-probes 20", normalized_unix)
        self.assertIn("--timeout 300", normalized_unix)
        self.assertIn("'--strict-probes', '20'", windows)
        self.assertIn("'--timeout', '300'", windows)

    def test_hindsight_acceptance_image_uses_the_bundled_hermes_environment(
        self,
    ) -> None:
        dockerfile = HERMES_DOCKERFILE.read_text(encoding="utf-8")
        acceptance = HINDSIGHT_ACCEPTANCE.read_text(encoding="utf-8")

        self.assertTrue(acceptance.startswith("#!/opt/hermes/.venv/bin/python\n"))
        self.assertIn(
            "COPY hindsight_acceptance.py /usr/local/bin/hermes-hindsight-acceptance",
            dockerfile,
        )
        self.assertIn(
            "chmod 0755 /usr/local/bin/hermes-hindsight-acceptance",
            dockerfile,
        )
        self.assertIn(
            "COPY hindsight_acceptance.py /workspace/docker/hermes-agent/hindsight_acceptance.py",
            dockerfile,
        )

    def _task_block(self, task_name: str) -> str:
        marker = f"  {task_name}:\n"
        start = self.taskfile.find(marker)
        self.assertNotEqual(start, -1, f"Task is missing: {task_name}")
        next_task = self.taskfile.find("\n  ", start + len(marker))
        while next_task != -1:
            line_end = self.taskfile.find("\n", next_task + 1)
            line = self.taskfile[next_task + 1 : line_end if line_end != -1 else None]
            if (
                line.startswith("  ")
                and not line.startswith("    ")
                and line.endswith(":")
            ):
                break
            next_task = self.taskfile.find("\n  ", next_task + 3)
        end = len(self.taskfile) if next_task == -1 else next_task + 1
        return self.taskfile[start:end]

    def _assert_in_order(self, text: str, tokens: tuple[str, ...]) -> None:
        position = -1
        for token in tokens:
            next_position = text.find(token, position + 1)
            self.assertNotEqual(
                next_position, -1, f"Missing ordered phase token: {token}"
            )
            self.assertGreater(next_position, position)
            position = next_position

    def _command_text(self, task_name: str) -> str:
        return self._task_block(task_name)


if __name__ == "__main__":
    unittest.main()
