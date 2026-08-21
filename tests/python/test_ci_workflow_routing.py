"""Contract tests for the lightweight CI routing workflow."""

from __future__ import annotations

import re
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
WORKFLOW_PATH = REPOSITORY_ROOT / ".github" / "workflows" / "ci-contract.yml"
WORKFLOWS_DIRECTORY = WORKFLOW_PATH.parent
PRE_COMMIT_PATH = REPOSITORY_ROOT / ".pre-commit-config.yaml"
HERMES_TASKFILE_PATH = REPOSITORY_ROOT / "taskfiles" / "hermes" / "taskfile.yml"
CHECKOUT_ACTION = "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"
SETUP_PYTHON_ACTION = "actions/setup-python@ece7cb06caefa5fff74198d8649806c4678c61a1"
INSTALL_NIX_ACTION = "cachix/install-nix-action@630ae543ea3a38a9a4166f03376c02c50f408342"


class CiWorkflowRoutingContractTests(unittest.TestCase):
    """Keep the lightweight CI workflow's trigger and tool contracts stable."""

    def _workflow(self) -> str:
        self.assertTrue(WORKFLOW_PATH.is_file(), f"missing workflow: {WORKFLOW_PATH}")
        return WORKFLOW_PATH.read_text(encoding="utf-8")

    def _named_workflow(self, name: str) -> str:
        path = WORKFLOWS_DIRECTORY / name
        self.assertTrue(path.is_file(), f"missing workflow: {path}")
        return path.read_text(encoding="utf-8")

    def _trigger_paths(self, workflow: str, event: str) -> str:
        match = re.search(
            rf"(?ms)^  {re.escape(event)}:\n"
            r"\s+branches: \[main\]\n"
            r"\s+paths:\n(?P<paths>.*?)(?=^  (?:push|pull_request):|^concurrency:)",
            workflow,
        )
        self.assertIsNotNone(match, f"missing {event} path filter")
        return match.group("paths") if match is not None else ""

    def test_pull_requests_to_main_always_run_ci_contract(self) -> None:
        workflow = self._workflow()
        self.assertIn("name: CI Contract", workflow)
        self.assertRegex(
            workflow,
            r"(?ms)^\s*pull_request:\n\s*branches: \[main\]\n(?!\s*paths:)",
        )
        self.assertRegex(workflow, r"(?m)^\s+ci-contract:\n\s+name: CI Contract$")

    def test_push_watches_routing_infrastructure_and_contract_tests(self) -> None:
        workflow = self._workflow()
        push_match = re.search(
            r"(?ms)^  push:\n(?P<section>.*?)(?=^permissions:)", workflow
        )
        self.assertIsNotNone(push_match)
        push_section = push_match.group("section") if push_match is not None else ""
        for path in (
            "ci/path-routing.json",
            "scripts/python/detect_ci_changes.py",
            ".github/actions/detect-ci-changes/**",
            ".github/workflows/**",
            "tests/bash/**",
            "tests/python/**",
        ):
            self.assertIn(path, push_section)

    def test_pins_checkout_python_and_nix_setup(self) -> None:
        workflow = self._workflow()
        self.assertIn(CHECKOUT_ACTION, workflow)
        self.assertIn(SETUP_PYTHON_ACTION, workflow)
        self.assertIn('python-version: "3.14"', workflow)
        self.assertIn(INSTALL_NIX_ACTION, workflow)

    def test_installs_bats_1_13_0_and_runs_only_routing_contracts(self) -> None:
        workflow = self._workflow()
        self.assertIn("bats_version='1.13.0'", workflow)
        self.assertIn(
            "https://github.com/bats-core/bats-core/archive/refs/tags/v$bats_version.tar.gz",
            workflow,
        )
        bats_lines = [
            line.strip()
            for line in workflow.splitlines()
            if "bats --print-output-on-failure" in line
        ]
        self.assertIn(
            "bats --print-output-on-failure tests/bash/ci_routing.bats",
            bats_lines,
        )
        self.assertNotRegex(
            workflow,
            r"(?m)^\s*(?:env -u DOTFILES_USER -u DOTFILES_HOME -u SUDO_USER )?"
            r"bats --print-output-on-failure tests/bash$",
        )

    def test_runs_focused_actionlint_and_python_discovery(self) -> None:
        workflow = self._workflow()
        actionlint_lines = [
            line.strip()
            for line in workflow.splitlines()
            if "go run github.com/rhysd/actionlint" in line
        ]
        self.assertIn(
            "run: go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.12 "
            ".github/workflows/ci-contract.yml",
            actionlint_lines,
        )
        self.assertNotIn(
            "run: go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.12",
            actionlint_lines,
        )
        self.assertIn("python -m unittest discover -s tests/python -v", workflow)

    def test_nix_ci_watches_only_nix_embedded_shell_scripts(self) -> None:
        workflow = self._named_workflow("ci-nix.yml")
        required_scripts = (
            "scripts/sh/dcnvim.sh",
            "scripts/sh/install-wezterm-nightly.sh",
            "scripts/sh/uninstall-arc-browser.sh",
        )

        for event in ("push", "pull_request"):
            paths = self._trigger_paths(workflow, event)
            for script in required_scripts:
                self.assertIn(script, paths)
            self.assertNotIn("scripts/sh/**", paths)
            self.assertNotIn("tests/bash/**", paths)

    def test_devcontainer_ci_ignores_generic_bats_changes(self) -> None:
        workflow = self._named_workflow("ci-devcontainer.yml")

        for event in ("push", "pull_request"):
            paths = self._trigger_paths(workflow, event)
            self.assertIn("scripts/sh/dcnvim.sh", paths)
            self.assertNotIn("tests/bash/**", paths)

    def test_hermes_ci_routes_xapi_contract_and_platform_adapters(self) -> None:
        workflow = self._named_workflow("ci-hermes-bootstrap.yml")
        required_paths = (
            "docker/hermes-agent/**",
            "docker/hermes-browser/**",
            "docker/hermes-browser-mcp/**",
            "docker/hermes-xapi-mcp/**",
            "scripts/sh/hermes-agent.sh",
            "scripts/powershell/handlers/Handler.HermesAgent.ps1",
            "tests/python/test_xapi_image_contract.py",
        )

        for event in ("push", "pull_request"):
            paths = self._trigger_paths(workflow, event)
            for required_path in required_paths:
                self.assertIn(required_path, paths)
        self.assertIn(
            "python3 -m unittest tests/python/test_xapi_image_contract.py -v",
            workflow,
        )

    def test_hermes_hook_and_task_run_xapi_image_contract(self) -> None:
        pre_commit = PRE_COMMIT_PATH.read_text(encoding="utf-8")
        taskfile = HERMES_TASKFILE_PATH.read_text(encoding="utf-8")

        hook = pre_commit.split("      - id: hermes-bootstrap-tests\n", maxsplit=1)[1]
        hook = hook.split("\n      - id:", maxsplit=1)[0]
        match = re.search(
            r"^\s+files:\s+'(?P<pattern>.+)'$",
            hook,
            flags=re.MULTILINE,
        )
        self.assertIsNotNone(match)
        pattern = match.group("pattern") if match is not None else ""
        for path in (
            "docker/hermes-xapi-mcp/Dockerfile",
            "tests/python/test_xapi_image_contract.py",
        ):
            self.assertIsNotNone(re.fullmatch(pattern, path))

        task = taskfile.split("  hermes:bootstrap:test:\n", maxsplit=1)[1]
        task = task.split("\n  hermes:bootstrap:config:\n", maxsplit=1)[0]
        self.assertIn(
            "python3 -m unittest tests/python/test_xapi_image_contract.py -v",
            task,
        )
        self.assertIn(
            "python -m unittest tests/python/test_xapi_image_contract.py -v",
            task,
        )


if __name__ == "__main__":
    unittest.main()
