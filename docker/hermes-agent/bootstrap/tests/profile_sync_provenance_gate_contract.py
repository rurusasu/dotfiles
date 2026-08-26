from __future__ import annotations

import json
import re
import unittest
from pathlib import Path


DOTFILES_ROOT = Path(__file__).resolve().parents[4]
HERMES_TASKFILE = DOTFILES_ROOT / "taskfiles" / "hermes" / "taskfile.yml"
BOOTSTRAP_WORKFLOW = DOTFILES_ROOT / ".github/workflows/ci-hermes-bootstrap.yml"
WORKFLOW = DOTFILES_ROOT / ".github/workflows/ci-hermes-provenance.yml"
PRE_COMMIT = DOTFILES_ROOT / ".pre-commit-config.yaml"
PROVENANCE = (
    DOTFILES_ROOT
    / "docker/hermes-agent/bootstrap/tests/fixtures/hermes-home"
    / "profile_sync.provenance.json"
)
VERIFIER_COMMAND = (
    "docker/hermes-agent/bootstrap/tests/verify_profile_sync_provenance.py"
)
PRE_COMMIT_TRIGGER = (
    r"^(docker/hermes-agent/.*|docker/hermes-xapi-mcp/.*|"
    r"scripts/sh/hermes-agent\.sh|"
    r"scripts/powershell/handlers/Handler\.HermesAgent\.ps1|"
    r"tests/python/test_xapi_image_contract\.py|taskfiles/hermes/taskfile\.yml|Taskfile\.yml|"
    r"\.pre-commit-config\.yaml|"
    r"\.github/workflows/ci-hermes-bootstrap\.yml|"
    r"\.github/workflows/ci-hermes-provenance\.yml)$"
)


class ProfileSyncProvenanceGateContractTests(unittest.TestCase):
    def test_task_runs_xapi_contract_before_container_suites(self) -> None:
        taskfile = HERMES_TASKFILE.read_text(encoding="utf-8")
        section = taskfile.split("  hermes:bootstrap:test:\n", maxsplit=1)[1]
        section, container_section = section.split(
            "\n  hermes:bootstrap:test:container:\n",
            maxsplit=1,
        )
        container_section = container_section.split(
            "\n  hermes:bootstrap:config:\n",
            maxsplit=1,
        )[0]

        xapi_windows_index = section.index(
            "python -m unittest tests/python/test_xapi_image_contract.py -v"
        )
        xapi_unix_index = section.index(
            "python3 -m unittest tests/python/test_xapi_image_contract.py -v"
        )
        container_task_index = section.index("task: hermes:bootstrap:test:container")
        gh_index = container_section.index(
            "docker/hermes-agent/bootstrap/tests/test_gh_wrapper.sh"
        )
        contract_index = container_section.index(
            "profile_sync_provenance_gate_contract.py"
        )
        verifier_index = container_section.index(VERIFIER_COMMAND)

        self.assertNotIn("docker info", section)
        self.assertNotIn("docker build", section)
        self.assertLess(xapi_windows_index, container_task_index)
        self.assertLess(xapi_unix_index, container_task_index)
        self.assertIn('PROVENANCE_URL: "{{.PROVENANCE_URL}}"', section)
        self.assertIn(
            'msg: "Docker daemon is not running. Start Docker Desktop and try again."',
            container_section,
        )
        self.assertIn("- sh: docker info", container_section)
        self.assertLess(gh_index, contract_index)
        self.assertLess(contract_index, verifier_index)
        self.assertIn(
            "{{.HERMES_HOME_PROVENANCE_URL "
            '| default "https://github.com/rurusasu/hermes-home.git"}}',
            section,
        )
        self.assertIn(
            '--source-url "{{.PROVENANCE_URL}}"',
            container_section,
        )

        pre_commit = PRE_COMMIT.read_text(encoding="utf-8")
        hook = pre_commit.split(
            "      - id: hermes-bootstrap-tests\n",
            maxsplit=1,
        )[1]
        hook = hook.split("\n      - id:", maxsplit=1)[0]
        self.assertIn("entry: task hermes:bootstrap:test", hook)

        filter_match = re.search(
            r"^\s+files:\s+(['\"])(?P<pattern>.+)\1\s*$",
            hook,
            flags=re.MULTILINE,
        )
        self.assertIsNotNone(filter_match)
        trigger = filter_match.group("pattern")
        self.assertEqual(trigger, PRE_COMMIT_TRIGGER)
        for changed_path in (
            "docker/hermes-agent/Dockerfile",
            "docker/hermes-xapi-mcp/Dockerfile",
            "scripts/sh/hermes-agent.sh",
            "scripts/powershell/handlers/Handler.HermesAgent.ps1",
            "tests/python/test_xapi_image_contract.py",
            "taskfiles/hermes/taskfile.yml",
            "Taskfile.yml",
            ".pre-commit-config.yaml",
            ".github/workflows/ci-hermes-bootstrap.yml",
            ".github/workflows/ci-hermes-provenance.yml",
        ):
            with self.subTest(changed_path=changed_path):
                self.assertIsNotNone(re.fullmatch(trigger, changed_path))
        self.assertIsNone(re.fullmatch(trigger, "docs/hermes-agent/bootstrap.md"))

    def test_workflow_fetches_only_the_validated_blob_and_runs_host_gate(
        self,
    ) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        bootstrap_workflow = BOOTSTRAP_WORKFLOW.read_text(encoding="utf-8")
        checkout_pins = re.findall(
            r"uses: actions/checkout@([0-9a-f]{40})",
            workflow,
        )
        provenance = json.loads(PROVENANCE.read_text(encoding="ascii"))

        self.assertEqual(len(checkout_pins), 1)
        self.assertEqual(len(set(checkout_pins)), 1)
        self.assertEqual(workflow.count("persist-credentials: false"), 1)
        self.assertNotIn("  pull_request:\n", workflow)
        self.assertNotIn("  workflow_dispatch:\n", workflow)
        self.assertNotIn("Checkout provenance-pinned hermes-home", workflow)
        self.assertNotIn("hermes-home-provenance", workflow)
        self.assertEqual(workflow.count("secrets.HERMES_HOME_READ_TOKEN"), 1)
        self.assertNotIn("HERMES_HOME_READ_TOKEN", bootstrap_workflow)
        self.assertNotIn(provenance["source_commit"], workflow)
        self.assertNotIn("id: provenance", workflow)
        self.assertIn(
            f"{VERIFIER_COMMAND} verify --dotfiles-repository .",
            workflow,
        )
        self.assertIn(
            "HERMES_HOME_READ_TOKEN: "
            "${{ secrets.HERMES_HOME_READ_TOKEN }}",
            workflow,
        )
        self.assertIn(
            '--source-url "https://github.com/rurusasu/hermes-home.git"',
            workflow,
        )
        self.assertIn('"Taskfile.yml"', workflow)
        self.assertIn('"taskfiles/hermes/taskfile.yml"', workflow)
        self.assertIn('".pre-commit-config.yaml"', workflow)


if __name__ == "__main__":
    unittest.main()
