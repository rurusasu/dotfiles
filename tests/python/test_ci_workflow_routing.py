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
CHEZMOI_WORKFLOW = "ci-chezmoi.yml"
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

    def _workflow_job(self, workflow: str, name: str) -> str:
        job = re.search(
            rf"(?ms)^  {re.escape(name)}:\n(?P<job>.*?)(?=^  [a-zA-Z0-9_-]+:\s*$|\Z)",
            workflow,
        )
        self.assertIsNotNone(job, f"missing {name} job")
        return job.group("job") if job is not None else ""

    def _assert_single_chezmoi_path_occurrence(
        self,
        workflow: str,
        lint: str,
    ) -> None:
        normalized_workflow = workflow.casefold().replace("\\", "/")
        normalized_lint = lint.casefold().replace("\\", "/")
        self.assertEqual(normalized_workflow.count("tests/chezmoi"), 1)
        self.assertEqual(normalized_lint.count("tests/chezmoi"), 1)

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
            "ci/bootstrap-path-routing.json",
            "scripts/python/detect_ci_changes.py",
            ".github/actions/detect-ci-changes/**",
            ".github/workflows/**",
            "tests/bash/**",
            "tests/python/**",
        ):
            self.assertIn(path, push_section)

    def test_change_detector_action_accepts_a_manifest_path(self) -> None:
        action_path = REPOSITORY_ROOT / ".github" / "actions" / "detect-ci-changes" / "action.yml"
        action = action_path.read_text(encoding="utf-8")

        self.assertIn("  manifest:\n", action)
        self.assertIn("default: ci/path-routing.json", action)
        self.assertIn('--manifest "${MANIFEST_PATH}"', action)

    def test_pins_checkout_python_and_nix_setup(self) -> None:
        workflow = self._workflow()
        self.assertIn(CHECKOUT_ACTION, workflow)
        self.assertIn(SETUP_PYTHON_ACTION, workflow)
        self.assertIn('python-version: "3.14"', workflow)
        self.assertIn(INSTALL_NIX_ACTION, workflow)

    def test_installs_bats_1_13_0_and_owns_every_safe_bats_file(self) -> None:
        workflow = self._workflow()
        self.assertIn("bats_version='1.13.0'", workflow)
        self.assertIn(
            "https://github.com/bats-core/bats-core/archive/refs/tags/v$bats_version.tar.gz",
            workflow,
        )
        self.assertIn("shopt -s nullglob", workflow)
        self.assertIn("bats_files=(tests/bash/*.bats)", workflow)
        self.assertIn("tests/bash/install_macos.bats", workflow)
        self.assertIn("tests/bash/install_linux.bats", workflow)
        self.assertIn('bats --print-output-on-failure "${bats_files[@]}"', workflow)
        all_bats_files = {path.name for path in (REPOSITORY_ROOT / "tests" / "bash").glob("*.bats")}
        excluded_bats_files = {"install_macos.bats", "install_linux.bats"}
        exclusion_case = re.search(
            r"(?ms)case \"\$\{bats_file\}\" in(?P<case>.*?)^\s*esac$",
            workflow,
        )
        self.assertIsNotNone(exclusion_case)
        case_body = exclusion_case.group("case") if exclusion_case is not None else ""
        self.assertEqual(
            set(re.findall(r"tests/bash/([^|)]+\.bats)", case_body)),
            excluded_bats_files,
        )
        self.assertIn("ci_routing.bats", all_bats_files - excluded_bats_files)
        self.assertGreater(len(all_bats_files - excluded_bats_files), 0)

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

    def test_bootstrap_workflow_watches_nix_validation_paths(self) -> None:
        workflow = self._named_workflow("ci-bootstrap.yml")
        for event in ("push", "pull_request"):
            paths = self._trigger_paths(workflow, event)
            self.assertIn('"scripts/sh/**"', paths)
            self.assertIn('".github/e2e/**"', paths)

    def test_bootstrap_workflow_integrates_nix_and_winget_validation(self) -> None:
        workflow = self._named_workflow("ci-bootstrap.yml")

        changes = self._workflow_job(workflow, "changes")
        self.assertIn("nix: ${{ steps.detect.outputs.nix }}", changes)

        for job_name, output in (
            ("nix-lint", "nix"),
            ("nix-format", "nix"),
            ("nix-test", "nix"),
            ("windows-installer", "windows"),
        ):
            job = self._workflow_job(workflow, job_name)
            self.assertIn(f"needs.changes.outputs.{output} == 'true'", job)

        self.assertIn("Bootstrap / Nix / Lint", workflow)
        self.assertIn("Bootstrap / Nix / Format", workflow)
        self.assertIn("Bootstrap / Nix / Test", workflow)
        self.assertIn("Bootstrap / Windows / Installer", workflow)

        complete = self._workflow_job(workflow, "complete")
        self.assertIn("NIX_REQUIRED", complete)
        self.assertIn("WINDOWS_INSTALLER_RESULT", complete)
        self.assertIn("nix-lint", complete)
        self.assertIn("nix-format", complete)
        self.assertIn("nix-test", complete)
        self.assertIn("windows-installer", complete)
        self.assertIn("check_required_job", complete)

        for event in ("push", "pull_request"):
            paths = self._trigger_paths(workflow, event)
            self.assertIn('"scripts/powershell/handlers/**"', paths)

    def test_legacy_nix_and_winget_workflows_are_removed(self) -> None:
        for name in ("ci-nix.yml", "ci-winget.yml"):
            self.assertFalse((WORKFLOWS_DIRECTORY / name).exists(), name)

    def test_devcontainer_ci_owns_only_the_two_excluded_bats_files(self) -> None:
        workflow = self._named_workflow("ci-devcontainer.yml")

        for event in ("push", "pull_request"):
            paths = self._trigger_paths(workflow, event)
            self.assertIn("scripts/sh/dcnvim.sh", paths)
            self.assertIn("tests/bash/install_macos.bats", paths)
            self.assertIn("tests/bash/install_linux.bats", paths)
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

    def test_unified_bootstrap_workflow_routes_all_platforms(self) -> None:
        workflow = self._named_workflow("ci-bootstrap.yml")

        self.assertIn("name: Bootstrap CI", workflow)
        self.assertIn("manifest: ci/bootstrap-path-routing.json", workflow)
        for output in ("linux", "darwin", "wsl", "windows"):
            self.assertRegex(
                workflow,
                rf"(?m)^\s+{output}: \$\{{\{{ steps\.detect\.outputs\.{output} \}}\}}$",
            )

        for marker in (
            "Bootstrap / Linux / Build",
            "Bootstrap / Linux / E2E / Ubuntu",
            "Bootstrap / Linux / E2E / Debian",
            "Bootstrap / Linux / E2E / NixOS",
            "Bootstrap / Darwin",
            "Bootstrap / WSL",
            "Bootstrap / Windows",
            "Bootstrap / Complete",
        ):
            self.assertIn(marker, workflow)

        for job_name, output in (
            ("linux-build", "linux"),
            ("darwin", "darwin"),
            ("wsl", "wsl"),
            ("windows", "windows"),
        ):
            job = self._workflow_job(workflow, job_name)
            self.assertIn("needs: changes", job)
            self.assertIn(f"needs.changes.outputs.{output} == 'true'", job)

        for job_name in ("linux-ubuntu", "linux-debian", "linux-nixos"):
            job = self._workflow_job(workflow, job_name)
            self.assertIn("needs: [changes, linux-build]", job)
            self.assertIn("needs.changes.outputs.linux == 'true'", job)

        complete = self._workflow_job(workflow, "complete")
        self.assertIn("if: ${{ always() }}", complete)
        self.assertNotIn("success|skipped", complete)

    def test_unified_bootstrap_workflow_fails_closed_for_selected_platforms(self) -> None:
        workflow = self._named_workflow("ci-bootstrap.yml")

        for event in ("push", "pull_request"):
            paths = self._trigger_paths(workflow, event)
            self.assertIn('      - "Taskfile.yml"', paths)
            self.assertIn('      - "taskfiles/**"', paths)

        changes = self._workflow_job(workflow, "changes")
        self.assertIn("platforms:", changes)

        complete = self._workflow_job(workflow, "complete")
        self.assertIn("PLATFORM_REQUIRED", complete)
        self.assertIn("LINUX_REQUIRED", complete)
        self.assertIn("WSL_REQUIRED", complete)
        self.assertIn("check_platform", complete)
        self.assertNotIn("success|skipped", complete)

        for job_name in (
            "linux-build",
            "linux-ubuntu",
            "linux-debian",
            "linux-nixos",
            "darwin",
            "wsl",
            "windows",
        ):
            job = self._workflow_job(workflow, job_name)
            self.assertIn("ref: ${{ env.TESTED_SHA }}", job)

    def test_chezmoi_ci_runs_pester_once_in_lint_and_uploads_its_junit_result(
        self,
    ) -> None:
        """Catch a second Chezmoi Pester job or a JUnit artifact detached from lint."""
        workflow = self._named_workflow(CHEZMOI_WORKFLOW)
        lint = self._workflow_job(workflow, "lint")
        fmt = self._workflow_job(workflow, "fmt")
        font_install = self._workflow_job(workflow, "font-install")
        op_guard = self._workflow_job(workflow, "op-guard")

        self.assertIsNone(
            re.search(r"(?m)^  test:\s*$", workflow),
            "Chezmoi CI must not define a duplicate top-level test job",
        )
        pester_invocation = (
            r"(?m)^          \.\\tests\\Invoke-Tests\.ps1 -Path "
            r"\.\\tests\\chezmoi -MinimumCoverage 0 -OutputFile "
            r"chezmoi-test-results\.xml$"
        )
        self._assert_single_chezmoi_path_occurrence(workflow, lint)
        self.assertRegex(lint, pester_invocation)
        canonical_invocation = (
            ".\\tests\\Invoke-Tests.ps1 -Path .\\tests\\chezmoi -MinimumCoverage 0 "
            "-OutputFile chezmoi-test-results.xml"
        )
        for alternate_invocation in (
            "      - run: >-\n"
            "          Invoke-Pester -Path .\\tests\\CHEZMOI",
            "      - run: Invoke-Pester -Path ./tests/chezmoi",
        ):
            mutated_workflow = workflow.replace(
                canonical_invocation,
                f"{canonical_invocation}\n{alternate_invocation}",
                1,
            )
            mutated_lint = self._workflow_job(mutated_workflow, "lint")
            with self.assertRaises(AssertionError):
                self._assert_single_chezmoi_path_occurrence(
                    mutated_workflow,
                    mutated_lint,
                )

        for job, required_name in (
            (lint, "Lint (Pester chezmoi)"),
            (fmt, "Format (.tmpl BOM check)"),
            (op_guard, "Render guard (op unauthenticated)"),
        ):
            self.assertRegex(job, rf"(?m)^    name: {re.escape(required_name)}$")
        self.assertRegex(font_install, r"(?m)^    name: Font install smoke \(Windows\)$")

        self.assertRegex(
            lint,
            r"(?ms)^      - name: Upload test results\n"
            r"        uses: actions/upload-artifact@[0-9a-f]{40}.*?\n"
            r"        if: always\(\)\n"
            r"        with:\n"
            r"          name: chezmoi-test-results\n"
            r"          path: scripts/powershell/chezmoi-test-results\.xml$",
        )


if __name__ == "__main__":
    unittest.main()
