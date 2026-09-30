"""Taskfile contracts for Hermes lifecycle operations."""

from __future__ import annotations

import subprocess
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
TASKFILE = REPOSITORY_ROOT / "Taskfile.yml"
GIT_TASKFILE = REPOSITORY_ROOT / "taskfiles" / "git" / "taskfile.yml"
HERMES_TASKFILE = REPOSITORY_ROOT / "taskfiles" / "hermes" / "taskfile.yml"
HERMES_AGENT = REPOSITORY_ROOT / "scripts" / "sh" / "hermes-agent.sh"
XAPI_WRAPPER = REPOSITORY_ROOT / "scripts" / "sh" / "hermes-xapi.sh"
XAPI_WINDOWS_WRAPPER = REPOSITORY_ROOT / "scripts" / "powershell" / "hermes-xapi.ps1"


class TaskfileContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.taskfile = "\n".join(
            path.read_text(encoding="utf-8")
            for path in (TASKFILE, GIT_TASKFILE, HERMES_TASKFILE)
        )

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
        self.assertIn("hermes gateway start", self._command_text("hermes:up"))
        self.assertNotIn("scripts/sh/hermes-xapi.sh up", self._command_text("hermes:up"))
        self.assertNotIn(
            "scripts/powershell/hermes-xapi.ps1 -Action up",
            self._command_text("hermes:up"),
        )
        self.assertIn(
            "logs -f --tail=100 xapi-mcp",
            self._command_text("hermes:xapi:logs"),
        )

    def test_native_bootstrap_tasks_do_not_require_docker_backend(self) -> None:
        self.assertIn("scripts/sh/hermes-bootstrap.sh apply", self._task_block("hermes:sync"))
        test_task = self._task_block("hermes:bootstrap:test")
        self.assertIn(".#checks.${system}.nix-unit", test_task)
        self.assertIn(".#checks.$system.nix-unit", test_task)
        self.assertNotIn("docker/hermes-agent", test_task)
        self.assertNotIn("hermes:docker:bootstrap", self.taskfile)

    def test_windows_gmail_auth_runs_in_the_wsl_hermes_home(self) -> None:
        task = self._command_text("hermes:gmail:auth")

        self.assertIn("{{.WSL}}bash -lc", task)
        self.assertIn("task hermes:gmail:auth", task)
        self.assertNotIn("scripts/powershell/hermes-gmail.ps1", task)

    def test_commit_runs_precommit_without_repeating_treefmt(self) -> None:
        commit = self._task_block("commit")

        self.assertIn("task: fmt", commit)
        self.assertIn("task: lint:no-format", commit)
        self.assertNotIn("task: lint\n", commit)

    def test_nix_tests_evaluate_current_system_once(self) -> None:
        taskfile = (
            REPOSITORY_ROOT / "taskfiles" / "test" / "taskfile.yml"
        ).read_text(encoding="utf-8")
        self.assertEqual(
            taskfile.count("nix eval --raw --impure --expr 'builtins.currentSystem'"),
            1,
        )

    def test_native_hermes_setup_starts_the_independent_memory_service(self) -> None:
        self.assertIn("task: hindsight:up", self._task_block("hermes:setup"))
        for profile in ("rick", "hoffman", "risarisa", "nancy"):
            with self.subTest(profile=profile):
                plan = self._task_plan(f"hermes:{profile}:up")

                self.assertIn("task: [hermes:up]", plan)
                self.assertIn(f"-p {profile} gateway status", plan)

    def test_desktop_entrypoint_uses_the_native_gateway(self) -> None:
        task = self._task_block("hermes:desktop")

        self.assertIn("open -a /Applications/Hermes.app", task)
        self.assertIn("platforms: [darwin]", task)
        self.assertNotIn("hermes-desktop-docker", task)

    def test_cli_entrypoint_uses_the_nix_managed_hermes_cli(self) -> None:
        task = self._task_block("hermes:cli")

        self.assertIn("interactive: true", task)
        self.assertIn("hermes {{range .CLI_ARGS_LIST}}", task)
        self.assertIn("CLI_ARGS_LIST", task)
        self.assertIn("shellQuote", task)
        self.assertIn("platforms: [darwin, linux]", task)
        self.assertNotIn("hermes-docker", task)

    def test_desktop_install_does_not_run_the_upstream_agent_installer(self) -> None:
        installer = (REPOSITORY_ROOT / "scripts" / "sh" / "hermes-desktop-install.sh").read_text(
            encoding="utf-8"
        )
        self.assertIn("nix-darwin cask", installer)
        self.assertIn("hermes --version", installer)
        self.assertNotIn("Hermes-Setup", installer)
        self.assertNotIn("open -n", installer)

    def test_profile_lifecycle_uses_the_root_multiplexer_and_profile_status(
        self,
    ) -> None:
        forbidden = r"-p\s+\S+\s+gateway\s+(?:start|run|stop|restart)"

        for action in ("status", "up", "down", "restart"):
            with self.subTest(action=action):
                plan = self._task_plan(
                    f"hermes:profile:{action}",
                    profile="personal-ops",
                )

                self.assertNotRegex(plan, forbidden)
                if action in ("status", "up", "restart"):
                    self.assertIn("-p personal-ops gateway status", plan)
                if action == "up":
                    self.assertIn("task: [hermes:up]", plan)
                if action == "restart":
                    self.assertIn("task: [hermes:restart]", plan)
                if action == "down":
                    self.assertIn(
                        "hermes gateway stop",
                        plan,
                    )

    def test_gateway_taskfile_never_targets_a_removed_compose_service(self) -> None:
        taskfile = HERMES_TASKFILE.read_text(encoding="utf-8")
        self.assertNotRegex(
            taskfile,
            r"docker compose[^\n]*\b(?:stop|restart|logs|run|exec)\b[^\n]*[ \t]hermes(?:[ \t]|$)",
        )
        hermes_module = (REPOSITORY_ROOT / "nix/home/hermes-agent.nix").read_text(
            encoding="utf-8"
        )
        self.assertIn("settings.gateway.multiplex_profiles", hermes_module)

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
        self.assertIn("dotfiles_hermes_run_with_service_account_cache", adapter)
        self.assertIn('OP_SERVICE_ACCOUNT_TOKEN="$token" "$@"', adapter)
        self.assertNotIn('signin --account "$account"', adapter)
        self.assertIn('item get "$item"', adapter)
        self.assertIn("jq -e -c", adapter)
        self.assertNotIn("jq -erce", adapter)
        self.assertNotIn("X_API_CLIENT_SECRET='", wrapper)

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

    def _task_plan(self, task_name: str, *, profile: str | None = None) -> str:
        command = [
            "task",
            "--dir",
            str(REPOSITORY_ROOT),
            "--dry",
            "--force",
            task_name,
        ]
        if profile is not None:
            command.append(f"PROFILE={profile}")
        completed = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(
            completed.returncode,
            0,
            completed.stdout + completed.stderr,
        )
        return completed.stdout + completed.stderr

    def _command_text(self, task_name: str) -> str:
        return self._task_block(task_name)


if __name__ == "__main__":
    unittest.main()
