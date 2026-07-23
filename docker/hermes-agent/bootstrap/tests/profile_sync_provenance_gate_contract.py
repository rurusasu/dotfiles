from __future__ import annotations

import json
import re
import unittest
from pathlib import Path


DOTFILES_ROOT = Path(__file__).resolve().parents[4]
TASKFILE = DOTFILES_ROOT / "Taskfile.yml"
WORKFLOW = DOTFILES_ROOT / ".github/workflows/ci-hermes-bootstrap.yml"
PRE_COMMIT = DOTFILES_ROOT / ".pre-commit-config.yaml"
PROVENANCE = (
    DOTFILES_ROOT
    / "docker/hermes-agent/bootstrap/tests/fixtures/hermes-home"
    / "profile_sync.provenance.json"
)
VERIFIER_COMMAND = (
    "docker/hermes-agent/bootstrap/tests/verify_profile_sync_provenance.py"
)


class ProfileSyncProvenanceGateContractTests(unittest.TestCase):
    def test_task_runs_the_host_gate_after_existing_suites(self) -> None:
        taskfile = TASKFILE.read_text(encoding="utf-8")
        section = taskfile.split("  hermes:bootstrap:test:\n", maxsplit=1)[1]
        section = section.split("\n  hermes:bootstrap:config:\n", maxsplit=1)[0]

        container_index = section.index("docker build --target hermes-bootstrap-test")
        gh_index = section.index(
            "docker/hermes-agent/bootstrap/tests/test_gh_wrapper.sh"
        )
        contract_index = section.index("profile_sync_provenance_gate_contract.py")
        verifier_index = section.index(VERIFIER_COMMAND)

        self.assertLess(container_index, gh_index)
        self.assertLess(gh_index, contract_index)
        self.assertLess(contract_index, verifier_index)
        self.assertIn(
            "{{.HERMES_HOME_PROVENANCE_REPOSITORY "
            '| default "../hermes-home-profile-sync"}}',
            section,
        )
        self.assertIn(
            '--source-repository "{{.PROVENANCE_REPOSITORY}}"',
            section,
        )

        pre_commit = PRE_COMMIT.read_text(encoding="utf-8")
        self.assertRegex(
            pre_commit,
            r"id: hermes-bootstrap-tests[\s\S]+?"
            r"entry: task hermes:bootstrap:test",
        )

    def test_workflow_checks_out_the_validated_commit_and_runs_host_gate(
        self,
    ) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        checkout_pins = re.findall(
            r"uses: actions/checkout@([0-9a-f]{40})",
            workflow,
        )
        provenance = json.loads(PROVENANCE.read_text(encoding="ascii"))

        self.assertEqual(len(checkout_pins), 2)
        self.assertEqual(len(set(checkout_pins)), 1)
        self.assertEqual(workflow.count("persist-credentials: false"), 2)
        self.assertIn('repository: "rurusasu/hermes-home"', workflow)
        self.assertIn(
            "ref: ${{ steps.provenance.outputs.source_commit }}",
            workflow,
        )
        self.assertIn("path: hermes-home-provenance", workflow)
        self.assertNotIn(provenance["source_commit"], workflow)
        self.assertIn("id: provenance", workflow)
        self.assertIn(
            f"{VERIFIER_COMMAND} source-commit --dotfiles-repository .",
            workflow,
        )
        self.assertIn(
            f"{VERIFIER_COMMAND} verify --dotfiles-repository .",
            workflow,
        )
        self.assertIn(
            "HERMES_HOME_PROVENANCE_REPOSITORY: "
            "${{ github.workspace }}/hermes-home-provenance",
            workflow,
        )
        self.assertIn('"Taskfile.yml"', workflow)
        self.assertIn('".pre-commit-config.yaml"', workflow)


if __name__ == "__main__":
    unittest.main()
