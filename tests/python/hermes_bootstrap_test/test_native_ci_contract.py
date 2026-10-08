"""Keep native Hermes checks attached to the event's immutable source revision."""

import shlex
import unittest
from copy import deepcopy
from pathlib import Path
from unittest import mock

import yaml

ROOT = Path(__file__).resolve().parents[3]


class NativeCiContractTests(unittest.TestCase):
    def workflow(self, name: str) -> dict:
        return yaml.safe_load((ROOT / ".github" / "workflows" / name).read_text())

    def test_selected_source_validation_checkouts_use_the_event_head(self) -> None:
        for name in (
            "ci-chezmoi.yml",
            "ci-other.yml",
            "ci-nix.yml",
            "codeql.yml",
        ):
            with self.subTest(workflow=name):
                workflow = self.workflow(name)
                head_expression = "${{ github.event_name == 'pull_request' && github.event.pull_request.head.sha || github.sha }}"
                tested_sha = workflow.get("env", {}).get("TESTED_SHA")
                self.assertEqual(tested_sha, head_expression)
                expected_ref = "${{ env.TESTED_SHA }}"
                checkouts = [
                    (job_name, step)
                    for job_name, job in workflow["jobs"].items()
                    for step in job.get("steps", [])
                    if step.get("uses", "").startswith("actions/checkout@")
                ]
                self.assertTrue(checkouts)
                for job_name, step in checkouts:
                    with self.subTest(job=job_name):
                        self.assertEqual(step.get("with", {}).get("ref"), expected_ref)

    def test_hermes_detection_and_runtime_use_the_event_head(self) -> None:
        workflow = self.workflow("ci-nix.yml")
        self.assertEqual(
            workflow.get("env", {}).get("TESTED_SHA"),
            "${{ github.event_name == 'pull_request' && github.event.pull_request.head.sha || github.sha }}",
        )
        for name in ("changes", "hermes-bootstrap-tests"):
            with self.subTest(job=name):
                checkouts = [
                    step
                    for step in workflow["jobs"][name]["steps"]
                    if step.get("uses", "").startswith("actions/checkout@")
                ]
                self.assertEqual(len(checkouts), 1)
                self.assertEqual(
                    checkouts[0]["with"].get("ref"), "${{ env.TESTED_SHA }}"
                )

    def test_existing_darwin_job_executes_native_hermes_check_with_its_cache(
        self,
    ) -> None:
        workflow = self.workflow("ci-nix.yml")
        darwin = workflow["jobs"]["darwin"]
        commands = [
            shlex.split(command)
            for step in darwin["steps"]
            if "run" in step
            for command in step["run"].replace("\\\n", " ").splitlines()
            if ".#checks.aarch64-darwin.hermes-bootstrap-tests" in command
        ]
        self.assertEqual(len(commands), 1)
        command = commands[0]
        self.assertEqual(
            command[:2],
            ["nix", "build"],
        )
        self.assertEqual(
            command.count(".#checks.aarch64-darwin.hermes-bootstrap-tests"), 1
        )
        self.assertIn("--no-link", command)
        self.assertIn("--print-build-logs", command)
        options = [
            command[index + 1 : index + 3]
            for index, token in enumerate(command)
            if token == "--option"
        ]
        self.assertCountEqual(
            options,
            [
                ["extra-substituters", "$NUMTIDE_CACHE"],
                ["extra-trusted-public-keys", "$NUMTIDE_CACHE_KEY"],
            ],
        )

    def test_native_hermes_gate_rejects_its_missing_cache_or_duplicate_build(
        self,
    ) -> None:
        original = self.workflow("ci-nix.yml")
        for mutation in ("substituter", "key", "duplicate"):
            with self.subTest(mutation=mutation):
                workflow = deepcopy(original)
                step = next(
                    step
                    for step in workflow["jobs"]["darwin"]["steps"]
                    if ".#checks.aarch64-darwin.hermes-bootstrap-tests"
                    in step.get("run", "")
                )
                command = step["run"]
                if mutation == "duplicate":
                    step["run"] = command + "\n" + command
                else:
                    option = (
                        "extra-substituters"
                        if mutation == "substituter"
                        else "extra-trusted-public-keys"
                    )
                    step["run"] = command.replace(
                        f"--option {option} ", "--removed-option "
                    )
                with (
                    mock.patch.object(self, "workflow", return_value=workflow),
                    self.assertRaises(AssertionError),
                ):
                    self.test_existing_darwin_job_executes_native_hermes_check_with_its_cache()
