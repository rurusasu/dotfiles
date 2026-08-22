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
BOOTSTRAP_BUILD_WORKFLOW = "ci-bootstrap-build.yml"
HOSTED_BOOTSTRAP_E2E_WORKFLOW = "ci-bootstrap-e2e-hosted.yml"
LINUX_BOOTSTRAP_E2E_WORKFLOW = "ci-bootstrap-e2e-linux.yml"
NIXOS_WSL_E2E_WORKFLOW = "ci-nixos-wsl.yml"
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

    def _bootstrap_build_complete_script(self, workflow: str) -> str:
        complete_job = re.search(
            r"(?ms)^  complete:\n(?P<job>.*?)(?=^  [a-zA-Z0-9_-]+:\s*$|\Z)",
            workflow,
        )
        self.assertIsNotNone(complete_job, "missing complete job")
        complete = complete_job.group("job") if complete_job is not None else ""
        step = re.search(
            r"(?ms)^      - name: Verify routed job results\n"
            r"        run: \|\n(?P<script>.*?"
            r'^          echo "All required bootstrap outputs built successfully\."\n)',
            complete,
        )
        self.assertIsNotNone(step, "missing complete-job result verification step")
        return step.group("script") if step is not None else ""

    def _assert_bootstrap_build_failure_guards(self, complete_script: str) -> None:
        self.assertRegex(
            complete_script,
            r'(?m)^[ \t]+if \[\[ "\$\{CHANGES_RESULT\}" != "success" \]\]; then\n'
            r'^[ \t]+echo "CI change detection did not complete successfully: '
            r'\$\{CHANGES_RESULT\}"\n'
            r'^[ \t]+exit 1\n'
            r'^[ \t]+fi$',
        )
        self.assertRegex(
            complete_script,
            r'(?m)^[ \t]+for result in "\$\{LINUX_RESULT\}" "\$\{DARWIN_RESULT\}"; do\n'
            r'^[ \t]+case "\$\{result\}" in\n'
            r'^[ \t]+success\|skipped\) ;;\n'
            r'^[ \t]+\*\)\n'
            r'^[ \t]+echo "Bootstrap platform job did not complete successfully: '
            r'\$\{result\}"\n'
            r'^[ \t]+exit 1\n'
            r'^[ \t]+;;\n'
            r'^[ \t]+esac\n'
            r'^[ \t]+done$',
        )

    def _hosted_bootstrap_e2e_complete_script(self, workflow: str) -> str:
        complete_job = re.search(
            r"(?ms)^  complete:\n(?P<job>.*?)(?=^  [a-zA-Z0-9_-]+:\s*$|\Z)",
            workflow,
        )
        self.assertIsNotNone(complete_job, "missing hosted complete job")
        complete = complete_job.group("job") if complete_job is not None else ""
        step = re.search(
            r"(?ms)^      - name: Verify routed job results\n"
            r"(?:        env:\n.*?^        run: \|\n)(?P<script>.*?"
            r'^          echo "All required hosted bootstrap contracts completed successfully\."\n)',
            complete,
        )
        self.assertIsNotNone(step, "missing hosted complete-job result verification step")
        return step.group("script") if step is not None else ""

    def _assert_hosted_bootstrap_e2e_failure_guards(self, complete_script: str) -> None:
        self.assertRegex(
            complete_script,
            r'(?m)^[ \t]+if \[\[ "\$\{CHANGES_RESULT\}" != "success" \]\]; then\n'
            r'^[ \t]+echo "CI change detection did not complete successfully: '
            r'\$\{CHANGES_RESULT\}"\n'
            r'^[ \t]+exit 1\n'
            r'^[ \t]+fi$',
        )
        self.assertRegex(
            complete_script,
            r'(?m)^[ \t]+for result in "\$\{WINDOWS_RESULT\}" "\$\{MACOS_RESULT\}"; do\n'
            r'^[ \t]+case "\$\{result\}" in\n'
            r'^[ \t]+success\|skipped\) ;;\n'
            r'^[ \t]+\*\)\n'
            r'^[ \t]+echo "Hosted bootstrap platform job did not complete successfully: '
            r'\$\{result\}"\n'
            r'^[ \t]+exit 1\n'
            r'^[ \t]+;;\n'
            r'^[ \t]+esac\n'
            r'^[ \t]+done$',
        )

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

    def test_bootstrap_build_routes_platform_jobs_and_propagates_failures(self) -> None:
        """Catch missing platform gates or a complete job that masks detector failures."""
        workflow = self._named_workflow(BOOTSTRAP_BUILD_WORKFLOW)

        for event in ("push", "pull_request"):
            paths = self._trigger_paths(workflow, event)
            for routing_path in (
                "ci/path-routing.json",
                "scripts/python/detect_ci_changes.py",
                "tests/python/test_detect_ci_changes.py",
                ".github/actions/detect-ci-changes/**",
                ".github/workflows/ci-contract.yml",
                ".github/workflows/ci-bootstrap-build.yml",
            ):
                self.assertIn(routing_path, paths)

        changes_job = re.search(
            r"(?ms)^  changes:\n(?P<job>.*?)(?=^  [a-zA-Z0-9_-]+:\s*$|\Z)",
            workflow,
        )
        self.assertIsNotNone(changes_job, "missing changes job")
        changes = changes_job.group("job") if changes_job is not None else ""
        self.assertRegex(changes, r"(?m)^\s+linux: \$\{\{ steps\.detect\.outputs\.linux \}\}$")
        self.assertRegex(changes, r"(?m)^\s+darwin: \$\{\{ steps\.detect\.outputs\.darwin \}\}$")
        self.assertIn(CHECKOUT_ACTION, changes)
        self.assertRegex(changes, r"(?m)^\s+fetch-depth: 0$")
        self.assertIn("uses: ./.github/actions/detect-ci-changes", changes)
        self.assertIn(
            "github.event_name == 'pull_request' && github.event.pull_request.base.sha",
            changes,
        )
        self.assertIn("github.event.before", changes)
        self.assertIn(
            "github.event_name == 'pull_request' && github.event.pull_request.head.sha",
            changes,
        )
        self.assertIn("github.sha", changes)
        self.assertIn("run-all: ${{ github.event_name == 'workflow_dispatch' }}", changes)

        for job_name, output in (("linux", "linux"), ("darwin", "darwin")):
            job = re.search(
                rf"(?ms)^  {job_name}:\n(?P<job>.*?)(?=^  [a-zA-Z0-9_-]+:\s*$|\Z)",
                workflow,
            )
            self.assertIsNotNone(job, f"missing {job_name} job")
            job_body = job.group("job") if job is not None else ""
            self.assertRegex(job_body, r"(?m)^\s+needs: changes$")
            self.assertIn(
                f"needs.changes.outputs.{output} == 'true'",
                job_body,
            )

        complete_job = re.search(
            r"(?ms)^  complete:\n(?P<job>.*?)(?=^  [a-zA-Z0-9_-]+:\s*$|\Z)",
            workflow,
        )
        self.assertIsNotNone(complete_job, "missing complete job")
        complete = complete_job.group("job") if complete_job is not None else ""
        self.assertRegex(complete, r"(?m)^\s+if: \$\{\{ always\(\) \}\}$")
        self.assertRegex(complete, r"(?m)^\s+needs: \[changes, linux, darwin\]$")
        for result in ("changes", "linux", "darwin"):
            self.assertIn(f"needs.{result}.result", complete)

        complete_script = self._bootstrap_build_complete_script(workflow)
        self._assert_bootstrap_build_failure_guards(complete_script)

        changes_guard = re.search(
            r'(?ms)^[ \t]+if \[\[ "\$\{CHANGES_RESULT\}" != "success" \]\]; then\n'
            r'.*?^[ \t]+fi$',
            complete_script,
        )
        self.assertIsNotNone(changes_guard, "missing changes failure guard")
        without_changes_guard = complete_script.replace(
            changes_guard.group(0) if changes_guard is not None else "",
            "",
            1,
        )
        with self.assertRaises(AssertionError):
            self._assert_bootstrap_build_failure_guards(without_changes_guard)

        platform_default = re.search(
            r'(?ms)^[ \t]+\*\)\n.*?^[ \t]+;;$',
            complete_script,
        )
        self.assertIsNotNone(platform_default, "missing platform default failure branch")
        without_platform_default = complete_script.replace(
            platform_default.group(0) if platform_default is not None else "",
            "",
            1,
        )
        with self.assertRaises(AssertionError):
            self._assert_bootstrap_build_failure_guards(without_platform_default)

    def test_hosted_bootstrap_e2e_routes_platform_jobs_and_propagates_failures(self) -> None:
        """Catch missing hosted platform gates or a complete job that masks failures."""
        workflow = self._named_workflow(HOSTED_BOOTSTRAP_E2E_WORKFLOW)

        self.assertRegex(
            workflow,
            r"(?ms)^  pull_request:\n    branches: \[main\]\n(?!    paths:)",
        )
        self.assertRegex(workflow, r"(?m)^  workflow_dispatch:\s*$")
        self.assertIn(
            "protected-bootstrap-${{ github.event.pull_request.number || github.ref }}",
            workflow,
        )
        self.assertIn(
            "TESTED_SHA: ${{ github.event_name == 'pull_request' && "
            "github.event.pull_request.head.sha || github.sha }}",
            workflow,
        )

        changes_job = re.search(
            r"(?ms)^  changes:\n(?P<job>.*?)(?=^  [a-zA-Z0-9_-]+:\s*$|\Z)",
            workflow,
        )
        self.assertIsNotNone(changes_job, "missing hosted changes job")
        changes = changes_job.group("job") if changes_job is not None else ""
        for output in ("windows", "darwin"):
            self.assertRegex(
                changes,
                rf"(?m)^\s+{output}: \$\{{\{{ steps\.detect\.outputs\.{output} \}}\}}$",
            )
        self.assertIn(CHECKOUT_ACTION, changes)
        self.assertRegex(changes, r"(?m)^\s+fetch-depth: 0$")
        self.assertIn("uses: ./.github/actions/detect-ci-changes", changes)
        self.assertIn(
            "github.event_name == 'pull_request' && github.event.pull_request.base.sha",
            changes,
        )
        self.assertIn("github.event.before", changes)
        self.assertIn(
            "github.event_name == 'pull_request' && github.event.pull_request.head.sha",
            changes,
        )
        self.assertIn("github.sha", changes)
        self.assertIn("run-all: ${{ github.event_name == 'workflow_dispatch' }}", changes)

        for job_name, output in (("windows", "windows"), ("macos", "darwin")):
            job = re.search(
                rf"(?ms)^  {job_name}:\n(?P<job>.*?)(?=^  [a-zA-Z0-9_-]+:\s*$|\Z)",
                workflow,
            )
            self.assertIsNotNone(job, f"missing {job_name} job")
            job_body = job.group("job") if job is not None else ""
            self.assertRegex(job_body, r"(?m)^\s+needs: changes$")
            self.assertIn(
                f"needs.changes.outputs.{output} == 'true'",
                job_body,
            )
            self.assertIn("ref: ${{ env.TESTED_SHA }}", job_body)

        complete_job = re.search(
            r"(?ms)^  complete:\n(?P<job>.*?)(?=^  [a-zA-Z0-9_-]+:\s*$|\Z)",
            workflow,
        )
        self.assertIsNotNone(complete_job, "missing hosted complete job")
        complete = complete_job.group("job") if complete_job is not None else ""
        self.assertRegex(complete, r"(?m)^\s+name: Protected Bootstrap E2E$")
        self.assertRegex(complete, r"(?m)^\s+if: \$\{{ always\(\) \}\}$")
        self.assertRegex(complete, r"(?m)^\s+needs: \[changes, windows, macos\]$")
        for result in ("changes", "windows", "macos"):
            self.assertIn(f"needs.{result}.result", complete)

        complete_script = self._hosted_bootstrap_e2e_complete_script(workflow)
        self._assert_hosted_bootstrap_e2e_failure_guards(complete_script)

        changes_guard = re.search(
            r'(?ms)^[ \t]+if \[\[ "\$\{CHANGES_RESULT\}" != "success" \]\]; then\n'
            r'.*?^[ \t]+fi$',
            complete_script,
        )
        self.assertIsNotNone(changes_guard, "missing hosted changes failure guard")
        without_changes_guard = complete_script.replace(
            changes_guard.group(0) if changes_guard is not None else "",
            "",
            1,
        )
        with self.assertRaises(AssertionError):
            self._assert_hosted_bootstrap_e2e_failure_guards(without_changes_guard)

        platform_default = re.search(
            r'(?ms)^[ \t]+\*\)\n.*?^[ \t]+;;$',
            complete_script,
        )
        self.assertIsNotNone(platform_default, "missing hosted platform default failure branch")
        without_platform_default = complete_script.replace(
            platform_default.group(0) if platform_default is not None else "",
            "",
            1,
        )
        with self.assertRaises(AssertionError):
            self._assert_hosted_bootstrap_e2e_failure_guards(without_platform_default)

    def test_linux_and_wsl_e2e_route_platform_jobs_without_weakening_fork_protection(
        self,
    ) -> None:
        """Catch missing Linux/WSL gates or a WSL condition that bypasses fork protection."""
        routing_paths = (
            "ci/path-routing.json",
            "scripts/python/detect_ci_changes.py",
            "tests/python/test_detect_ci_changes.py",
            ".github/actions/detect-ci-changes/**",
            ".github/workflows/ci-contract.yml",
        )

        linux_workflow = self._named_workflow(LINUX_BOOTSTRAP_E2E_WORKFLOW)
        wsl_workflow = self._named_workflow(NIXOS_WSL_E2E_WORKFLOW)

        for workflow, workflow_path in (
            (linux_workflow, LINUX_BOOTSTRAP_E2E_WORKFLOW),
            (wsl_workflow, NIXOS_WSL_E2E_WORKFLOW),
        ):
            for event in ("push", "pull_request"):
                paths = self._trigger_paths(workflow, event)
                for routing_path in (*routing_paths, f".github/workflows/{workflow_path}"):
                    self.assertIn(routing_path, paths)

            changes_job = re.search(
                r"(?ms)^  changes:\n(?P<job>.*?)(?=^  [a-zA-Z0-9_-]+:\s*$|\Z)",
                workflow,
            )
            self.assertIsNotNone(changes_job, f"missing changes job in {workflow_path}")
            changes = changes_job.group("job") if changes_job is not None else ""
            self.assertIn(CHECKOUT_ACTION, changes)
            self.assertRegex(changes, r"(?m)^\s+fetch-depth: 0$")
            self.assertIn("uses: ./.github/actions/detect-ci-changes", changes)
            self.assertIn(
                "github.event_name == 'pull_request' && github.event.pull_request.base.sha",
                changes,
            )
            self.assertIn("github.event.before", changes)
            self.assertIn(
                "github.event_name == 'pull_request' && github.event.pull_request.head.sha",
                changes,
            )
            self.assertIn("github.sha", changes)
            self.assertIn("run-all: ${{ github.event_name == 'workflow_dispatch' }}", changes)

        for job_name in ("ubuntu", "debian", "nixos"):
            job = re.search(
                rf"(?ms)^  {job_name}:\n(?P<job>.*?)(?=^  [a-zA-Z0-9_-]+:\s*$|\Z)",
                linux_workflow,
            )
            self.assertIsNotNone(job, f"missing {job_name} job")
            job_body = job.group("job") if job is not None else ""
            self.assertRegex(job_body, r"(?m)^\s+needs: changes$")
            self.assertIn("needs.changes.outputs.linux == 'true'", job_body)

        for event in ("push", "pull_request"):
            activation_paths = self._trigger_paths(linux_workflow, event)
            self.assertIn("install.sh", activation_paths)
            self.assertIn("scripts/sh/**", activation_paths)
            self.assertIn(".github/e2e/**", activation_paths)

        switch = re.search(
            r"(?ms)^  switch:\n(?P<job>.*?)(?=^  [a-zA-Z0-9_-]+:\s*$|\Z)",
            wsl_workflow,
        )
        self.assertIsNotNone(switch, "missing WSL switch job")
        switch_body = switch.group("job") if switch is not None else ""
        self.assertRegex(switch_body, r"(?m)^\s+needs: changes$")
        self.assertRegex(
            switch_body,
            r"(?m)^\s+if: \$\{\{ needs\.changes\.outputs\.wsl == 'true' && "
            r"\(github\.event_name != 'pull_request' \|\| "
            r"github\.event\.pull_request\.head\.repo\.full_name == github\.repository\) \}\}$",
        )
        self.assertIn("HEAD_REF: ${{ github.head_ref }}", switch_body)
        self.assertIn("REF_NAME: ${{ github.ref_name }}", switch_body)
        self.assertIn("$refName = $env:HEAD_REF", switch_body)
        self.assertIn("$refName = $env:REF_NAME", switch_body)
        self.assertNotIn('$refName = "${{ github.head_ref }}"', switch_body)

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
