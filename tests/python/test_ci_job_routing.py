"""Behavioral tests for extension-aware jobs and required-check completion."""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from tests.python.test_detect_ci_changes import load_detector

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "ci/job-path-routing.json"
BOOTSTRAP = ROOT / "ci/bootstrap-path-routing.json"
JOBS = {
    "ci-chezmoi.yml": {
        "lint": "chezmoi_lint",
        "fmt": "templates",
        "font-install": "fonts",
        "op-guard": "templates",
    },
    "ci-powershell.yml": {
        "lint": "powershell_lint",
        "test": "powershell_test",
        "test-windows-powershell": "powershell_test",
    },
    "ci-consistency.yml": {"check": "package_catalog"},
    "ci-devcontainer.yml": {
        "linux-nix": "devcontainer",
        "macos": "devcontainer",
        "windows": "devcontainer",
    },
    "ci-hermes-bootstrap.yml": {"hermes-bootstrap-tests": "hermes"},
}


class CiJobRoutingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.detector = load_detector()

    def selected(self, *paths: str, manifest: Path = MANIFEST) -> set[str]:
        return {
            key
            for key, value in self.detector.route_paths(paths, manifest).items()
            if value
        }

    def test_python_test_only_does_not_start_platform_or_template_jobs(self) -> None:
        self.assertEqual(self.selected("tests/python/test_example.py"), {"python"})
        self.assertEqual(
            self.selected("tests/python/test_example.py", manifest=BOOTSTRAP),
            {"contract"},
        )

    def test_bash_test_selects_contracts_without_container_builds(self) -> None:
        self.assertEqual(self.selected("tests/bash/example.bats"), {"python", "bash"})

    def test_powershell_extensions_select_lint_and_contracts(self) -> None:
        for suffix in ("ps1", "psm1", "psd1"):
            with self.subTest(suffix=suffix):
                self.assertEqual(
                    self.selected(f"scripts/powershell/example.{suffix}"),
                    {"python", "bash", "powershell_lint", "powershell_test"},
                )

    def test_lua_does_not_select_template_or_font_jobs(self) -> None:
        self.assertEqual(
            self.selected("chezmoi/editors/nvim/init.lua"),
            {"python", "bash", "powershell_test", "chezmoi_lint"},
        )

    def test_double_extension_template_and_font_installer_are_detected(self) -> None:
        self.assertIn(
            "templates", self.selected("chezmoi/dot_config/example.json.tmpl")
        )
        selected = self.selected(
            "chezmoi/.chezmoiscripts/setup/fonts/run_onchange_before_00-install-udev-gothic.ps1.tmpl"
        )
        self.assertTrue({"fonts", "templates", "chezmoi_lint"}.issubset(selected))

    def test_shared_template_data_and_extensionless_files_are_dependencies(
        self,
    ) -> None:
        self.assertIn("templates", self.selected("chezmoi/.chezmoidata/packages.yaml"))
        self.assertIn("templates", self.selected("chezmoi/.chezmoitemplates/shared"))
        self.assertIn("hermes", self.selected("docker/hermes-agent/Dockerfile"))
        self.assertIn("chezmoi_lint", self.selected("chezmoi/shells/bashrc"))

    def test_nix_catalog_keeps_cross_language_contracts(self) -> None:
        selected = self.selected("nix/packages/sets.nix")
        self.assertTrue(
            {"package_catalog", "powershell_test", "chezmoi_lint"}.issubset(selected)
        )
        self.assertNotIn("powershell_lint", selected)
        self.assertNotIn("fonts", selected)

    def test_workflow_yaml_is_linted_but_regular_yaml_is_not(self) -> None:
        self.assertIn("actionlint", self.selected(".github/workflows/example.yaml"))
        self.assertNotIn("actionlint", self.selected("docker/mlflow/compose.yml"))

    def test_existing_workflow_dependencies_remain_selected(self) -> None:
        for path, output in (
            ("taskfiles/hermes/taskfile.yml", "hermes"),
            (".pre-commit-config.yaml", "hermes"),
            ("Taskfile.yml", "hermes"),
            ("scripts/sh/install-macos.sh", "devcontainer"),
            ("install.sh", "devcontainer"),
            ("chezmoi/dot_config/plane-github-sync/config.json", "powershell_test"),
            ("windows/npm/packages.json", "package_catalog"),
        ):
            with self.subTest(path=path):
                self.assertIn(output, self.selected(path))

    def test_mixed_changes_union_targets(self) -> None:
        paths = [
            "tests/python/test_example.py",
            "scripts/powershell/example.ps1",
            "chezmoi/dot_config/example.json.tmpl",
        ]
        self.assertEqual(
            self.selected(*paths), set().union(*(self.selected(p) for p in paths))
        )

    def test_documentation_skips_expensive_jobs_but_runtime_markdown_is_kept(
        self,
    ) -> None:
        for path in (
            "README.md",
            "nix/home/README.md",
            "scripts/powershell/README.md",
            "docker/hermes-agent/README.md",
            "chezmoi/README.md",
            "docs/mlflow/setup.md",
        ):
            with self.subTest(path=path):
                self.assertTrue(self.selected(path).issubset({"python", "bash"}))
                self.assertEqual(self.selected(path, manifest=BOOTSTRAP), {"contract"})
        self.assertIn(
            "hermes", self.selected("docker/hermes-agent/profiles/example/SOUL.md")
        )
        self.assertIn("chezmoi_lint", self.selected("chezmoi/dot_codex/AGENTS.md"))

    def test_unknown_bootstrap_runtime_path_keeps_conservative_fallback(self) -> None:
        self.assertTrue(
            {"linux", "darwin", "wsl", "windows"}.issubset(
                self.selected("scripts/sh/new-installer.sh", manifest=BOOTSTRAP)
            )
        )

    def test_routing_changes_and_manual_runs_cover_all_job_outputs(self) -> None:
        manifest = json.loads(MANIFEST.read_text())
        self.assertEqual(
            self.selected("ci/job-path-routing.json"), set(manifest["outputs"])
        )
        result = subprocess.run(
            [
                sys.executable,
                str(ROOT / "scripts/python/detect_ci_changes.py"),
                "--manifest",
                str(MANIFEST),
                "--all",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        self.assertTrue(all(json.loads(result.stdout).values()))

    def test_invalid_exclusions_and_undeclared_outputs_fail_closed(self) -> None:
        for mutate in (
            lambda m: m.update(ignored_patterns=["../outside"]),
            lambda m: m.update(fallback_patterns=["../outside"]),
            lambda m: m["rules"][0].update(exclude_patterns=["/absolute"]),
            lambda m: m["rules"][0].update(exclude_patterns="*.md"),
            lambda m: m["outputs"].remove("python"),
            lambda m: m["outputs"].append("python"),
        ):
            manifest = json.loads(MANIFEST.read_text())
            mutate(manifest)
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "routing.json"
                path.write_text(json.dumps(manifest))
                with self.assertRaises(ValueError):
                    self.selected("README.md", manifest=path)

    def test_workflows_keep_check_names_and_gate_jobs_after_detection(self) -> None:
        for filename, jobs in JOBS.items():
            workflow = (ROOT / ".github/workflows" / filename).read_text()
            with self.subTest(workflow=filename):
                triggers = workflow.split("\nconcurrency:")[0]
                self.assertNotIn("    paths:", triggers)
                self.assertIn("manifest: ci/job-path-routing.json", workflow)
                self.assertIn("fetch-depth: 0", workflow)
                self.assertIn("github.event_name == 'workflow_dispatch'", workflow)
                for job, output in jobs.items():
                    body = re.search(
                        rf"(?ms)^  {job}:\n(.*?)(?=^  [\w-]+:\n|\Z)", workflow
                    )[1]
                    self.assertRegex(body, r"needs: (changes|\[changes, lint\])")
                    self.assertIn(f"needs.changes.outputs.{output} == 'true'", body)
                    self.assertIn(
                        "always() && (needs.changes.result != 'success'", body
                    )
                    self.assertIn("name: Verify change detection", body)
                    self.assertIn("run: exit 1", body)

    def test_bootstrap_always_reports_on_pull_requests(self) -> None:
        workflow = (ROOT / ".github/workflows/ci-bootstrap.yml").read_text()
        trigger = workflow.split("  pull_request:\n", 1)[1].split("\nconcurrency:", 1)[
            0
        ]
        self.assertIn("branches: [main]", trigger)
        self.assertNotIn("paths:", trigger)

    def test_bootstrap_aggregate_accepts_no_work_but_rejects_missing_required_jobs(
        self,
    ) -> None:
        workflow = (ROOT / ".github/workflows/ci-bootstrap.yml").read_text()
        aggregate = workflow.split("  complete:\n", 1)[1]
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
            ({"LINUX_REQUIRED": "true"}, 1),
            ({"NIX_REQUIRED": "true"}, 1),
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
