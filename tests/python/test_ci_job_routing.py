"""Runtime checks for CI cancellation and the aggregate completion gate."""

from __future__ import annotations

import os
import re
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class CiJobRoutingTests(unittest.TestCase):
    def test_devcontainer_cancellation_stops_work_but_keeps_detection_fail_closed(
        self,
    ) -> None:
        workflow = (ROOT / ".github/workflows/ci-other.yml").read_text()
        for job in ("linux-nix", "windows"):
            body = re.search(rf"(?ms)^  {job}:\n(.*?)(?=^  [\w-]+:\n|\Z)", workflow)[1]
            expression = re.search(r"(?m)^    if: \$\{\{ (.*?) \}\}$", body)[1]
            # This predicate uses only boolean operators and string equality,
            # shared with Bash. Evaluate its actual operands, not a copied rule.
            expression = expression.replace("needs.changes.result", '"$CHANGES_RESULT"')
            expression = expression.replace("needs.changes.outputs.nix", '"$SELECTED"')
            expression = expression.replace(
                "needs.changes.outputs.other", '"$SELECTED"'
            )
            expression = expression.replace("!cancelled()", '"$CANCELLED" != "true"')
            expression = expression.replace("cancelled()", '"$CANCELLED" == "true"')
            expression = expression.replace("always()", '"true" == "true"')
            for status in ("success", "failure", "cancelled", "skipped", ""):
                for selected in ("true", "false"):
                    for cancelled in ("true", "false"):
                        with self.subTest(
                            job=job,
                            status=status,
                            selected=selected,
                            cancelled=cancelled,
                        ):
                            result = subprocess.run(
                                ["bash", "-c", f"[[ {expression} ]]"],
                                env=os.environ
                                | {
                                    "CHANGES_RESULT": status,
                                    "SELECTED": selected,
                                    "CANCELLED": cancelled,
                                },
                                capture_output=True,
                                text=True,
                                check=False,
                            )
                            run = status != "success" or (
                                selected == "true" and cancelled == "false"
                            )
                            self.assertEqual(
                                result.returncode, 0 if run else 1, result.stderr
                            )

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
