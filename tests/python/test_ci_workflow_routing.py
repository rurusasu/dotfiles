"""Contract tests for the lightweight CI routing workflow."""

from __future__ import annotations

import re
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
WORKFLOW_PATH = REPOSITORY_ROOT / ".github" / "workflows" / "ci-contract.yml"
CHECKOUT_ACTION = "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"
SETUP_PYTHON_ACTION = "actions/setup-python@ece7cb06caefa5fff74198d8649806c4678c61a1"
INSTALL_NIX_ACTION = "cachix/install-nix-action@630ae543ea3a38a9a4166f03376c02c50f408342"


class CiWorkflowRoutingContractTests(unittest.TestCase):
    """Keep the lightweight CI workflow's trigger and tool contracts stable."""

    def _workflow(self) -> str:
        self.assertTrue(WORKFLOW_PATH.is_file(), f"missing workflow: {WORKFLOW_PATH}")
        return WORKFLOW_PATH.read_text(encoding="utf-8")

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

    def test_installs_bats_1_13_0_and_runs_every_bats_contract(self) -> None:
        workflow = self._workflow()
        self.assertIn("bats_version='1.13.0'", workflow)
        self.assertIn(
            "https://github.com/bats-core/bats-core/archive/refs/tags/v$bats_version.tar.gz",
            workflow,
        )
        self.assertIn("bats --print-output-on-failure tests/bash", workflow)

    def test_runs_actionlint_and_python_discovery(self) -> None:
        workflow = self._workflow()
        self.assertIn(
            "go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.12",
            workflow,
        )
        self.assertIn("python -m unittest discover -s tests/python -v", workflow)


if __name__ == "__main__":
    unittest.main()
