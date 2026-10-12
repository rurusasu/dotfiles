"""Runtime checks for CI cancellation and the aggregate completion gate."""

from __future__ import annotations

import os
import re
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class CiJobRoutingTests(unittest.TestCase):
    def test_bootstrap_always_reports_on_pull_requests(self) -> None:
        workflow = (ROOT / ".github/workflows/ci-nix.yml").read_text()
        trigger = workflow.split("  pull_request:\n", 1)[1].split("\nconcurrency:", 1)[
            0
        ]
        self.assertIn("branches: [main]", trigger)
        self.assertNotIn("paths:", trigger)

    def test_bootstrap_aggregate_accepts_no_work_but_rejects_missing_required_jobs(
        self,
    ) -> None:
        workflow = (ROOT / ".github/workflows/ci-nix.yml").read_text()
        aggregate = re.search(r"(?ms)^  complete:\n(.*?)(?=^  [\w-]+:\n|\Z)", workflow)[
            1
        ]
        script = aggregate.split("        run: |\n", 1)[1]
        script = "\n".join(line[10:] for line in script.splitlines())
        variables = set(re.findall(r"\$\{([A-Z_]+)\}", script))
        env = (
            os.environ
            | {
                key: "skipped" if key.endswith("_RESULT") else "false"
                for key in variables
            }
            | {"CHANGES_RESULT": "success"}
        )
        for changes, expected in (
            ({}, 0),
            ({"CHANGES_RESULT": "failure"}, 1),
            ({"LINUX_BUILD_REQUIRED": "true"}, 1),
            ({"NIX_REQUIRED": "true"}, 1),
            ({"BASH_REQUIRED": "true"}, 1),
            ({"BASH_REQUIRED": "true", "BASH_RESULT": "failure"}, 1),
            ({"BASH_REQUIRED": "true", "BASH_RESULT": "cancelled"}, 1),
            ({"BASH_REQUIRED": "true", "BASH_RESULT": "success"}, 0),
            ({"BASH_RESULT": "success"}, 1),
            ({"HERMES_REQUIRED": "true"}, 1),
            ({"HERMES_REQUIRED": "true", "HERMES_RESULT": ""}, 1),
            ({"HERMES_REQUIRED": "true", "HERMES_RESULT": "failure"}, 1),
            ({"HERMES_REQUIRED": "true", "HERMES_RESULT": "cancelled"}, 1),
            ({"HERMES_REQUIRED": "true", "HERMES_RESULT": "success"}, 0),
            ({"HERMES_RESULT": "success"}, 1),
            (
                {
                    "TOOLS_REQUIRED": "true",
                    "TOOLS_RESULT": "success",
                    "NIX_REQUIRED": "true",
                    "NIX_RESULT": "success",
                    "LINUX_BUILD_REQUIRED": "true",
                    "LINUX_BUILD_RESULT": "success",
                },
                0,
            ),
            (
                {
                    "TOOLS_REQUIRED": "true",
                    "TOOLS_RESULT": "success",
                    "NIX_REQUIRED": "true",
                    "NIX_RESULT": "failure",
                    "LINUX_BUILD_REQUIRED": "true",
                    "LINUX_BUILD_RESULT": "success",
                },
                1,
            ),
            (
                {
                    "TOOLS_REQUIRED": "true",
                    "TOOLS_RESULT": "success",
                    "NIX_REQUIRED": "true",
                    "NIX_RESULT": "success",
                    "LINUX_BUILD_REQUIRED": "true",
                },
                1,
            ),
            ({"WINDOWS_REQUIRED": "true"}, 1),
            ({"WINDOWS_REQUIRED": "true", "WINDOWS_INSTALLER_RESULT": ""}, 1),
            ({"WINDOWS_REQUIRED": "true", "WINDOWS_INSTALLER_RESULT": "queued"}, 1),
            ({"WINDOWS_REQUIRED": "true", "WINDOWS_INSTALLER_RESULT": "failure"}, 1),
            ({"WINDOWS_REQUIRED": "true", "WINDOWS_INSTALLER_RESULT": "cancelled"}, 1),
            ({"WINDOWS_REQUIRED": "true", "WINDOWS_INSTALLER_RESULT": "timed_out"}, 1),
            ({"WINDOWS_REQUIRED": "true", "WINDOWS_INSTALLER_RESULT": "success"}, 0),
            ({"WINDOWS_INSTALLER_RESULT": "success"}, 1),
            ({"DARWIN_RESULT": "success"}, 1),
        ):
            with self.subTest(changes=changes):
                result = subprocess.run(
                    ["bash", "-c", script],
                    env=env | changes,
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(
                    result.returncode, expected, result.stdout + result.stderr
                )


if __name__ == "__main__":
    unittest.main()
