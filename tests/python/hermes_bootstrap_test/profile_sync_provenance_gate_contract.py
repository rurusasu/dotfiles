from __future__ import annotations

import re
import unittest
from pathlib import Path


DOTFILES_ROOT = Path(__file__).resolve().parents[3]
TASKFILE = DOTFILES_ROOT / "taskfiles/hermes/taskfile.yml"
WORKFLOW = DOTFILES_ROOT / ".github/workflows/ci-hermes-bootstrap.yml"
PROVENANCE_WORKFLOW = DOTFILES_ROOT / ".github/workflows/ci-hermes-provenance.yml"
PRE_COMMIT = DOTFILES_ROOT / ".pre-commit-config.yaml"
PROVENANCE_FIXTURE = (
    DOTFILES_ROOT
    / "tests/python/hermes_bootstrap_test/fixtures/hermes-home/profile_sync.provenance.json"
)
VERIFIER = "tests/python/hermes_bootstrap_test/verify_profile_sync_provenance.py"


class ProfileSyncProvenanceGateContractTests(unittest.TestCase):
    def test_native_task_runs_nix_python_and_shell_contracts(self) -> None:
        task = TASKFILE.read_text(encoding="utf-8")
        section = task.split("  hermes:bootstrap:test:\n", maxsplit=1)[1]
        section = section.split("\n  hermes:", maxsplit=1)[0]

        for required in (
            "nix build .#checks.nix-unit --no-link",
            "bats tests/bash/hermes_native_bootstrap.bats",
            "profile_sync_provenance_gate_contract.py",
            f"{VERIFIER} verify",
        ):
            with self.subTest(required=required):
                self.assertIn(required, section)
        self.assertNotIn("docker build", section)
        self.assertNotIn("docker info", section)
        self.assertNotIn("hermes:docker:", task)
        self.assertTrue(PROVENANCE_FIXTURE.is_file())

    def test_precommit_and_hosted_ci_run_native_provenance_verifier(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        provenance_workflow = PROVENANCE_WORKFLOW.read_text(encoding="utf-8")
        pre_commit = PRE_COMMIT.read_text(encoding="utf-8")
        hook = pre_commit.split(
            "      - id: hermes-bootstrap-tests\n", maxsplit=1
        )[1].split("\n      - id:", maxsplit=1)[0]
        match = re.search(r"^\s+files:\s+'(?P<pattern>.+)'$", hook, re.MULTILINE)
        self.assertIsNotNone(match)
        pattern = match.group("pattern") if match else ""

        for changed_path in (
            "scripts/python/hermes_bootstrap/app.py",
            "tests/python/hermes_bootstrap_test/test_app.py",
            "nix/home/hermes-agent.nix",
            "docker/hermes-xapi-mcp/Dockerfile",
            "docker/local-ai-services/compose.yml",
        ):
            with self.subTest(changed_path=changed_path):
                self.assertIsNotNone(re.fullmatch(pattern, changed_path))
        self.assertIn(VERIFIER, provenance_workflow)
        self.assertIn("nix build .#checks.x86_64-linux.hermes-bootstrap-tests", workflow)
        self.assertNotIn("docker/hermes-agent/Dockerfile", workflow)


if __name__ == "__main__":
    unittest.main()
