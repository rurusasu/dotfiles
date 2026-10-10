"""Contract tests for the lightweight CI routing workflow."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import textwrap
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
WORKFLOW_PATH = REPOSITORY_ROOT / ".github" / "workflows" / "ci-other.yml"
WORKFLOWS_DIRECTORY = WORKFLOW_PATH.parent
PRE_COMMIT_PATH = REPOSITORY_ROOT / ".pre-commit-config.yaml"
DEVCONTAINER_BATS_PATH = REPOSITORY_ROOT / ".devcontainer" / "ci" / "bats.sh"
HERMES_TASKFILE_PATH = REPOSITORY_ROOT / "taskfiles" / "hermes" / "taskfile.yml"
CHEZMOI_WORKFLOW = "ci-chezmoi.yml"
CHECKOUT_ACTION = "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"


class CiWorkflowRoutingContractTests(unittest.TestCase):
    """Keep the lightweight CI workflow's trigger and tool contracts stable."""

    def test_platform_jobs_use_rebuild_for_application_checks(self) -> None:
        workflow = self._named_workflow("ci-nix.yml")
        self.assertNotIn("linux-nixos:", workflow)
        self.assertNotIn("bootstrap-nixos-vm", workflow)
        complete = self._workflow_job(workflow, "complete")
        self.assertNotIn("LINUX_NIXOS_RESULT", complete)
        self.assertIn('check_required_job "Darwin"', complete)
        self.assertIn('check_required_job "WSL"', complete)

    def test_darwin_applies_configuration_through_nix_darwin(self) -> None:
        workflow = self._named_workflow("ci-nix.yml")
        darwin = self._workflow_job(workflow, "darwin")
        self.assertIn("name: Apply macOS configuration", darwin)
        self.assertIn("sudo nix --accept-flake-config", darwin)
        self.assertIn("run .#darwin-rebuild -- switch --flake .#macos --impure", darwin)
        self.assertNotIn("nix build", darwin)
        self.assertNotIn("Darwin application artifacts", darwin)
        self.assertIn("Configure shared Nix caches", darwin)

    def test_local_nix_checks_share_one_build_invocation(self) -> None:
        taskfile = (REPOSITORY_ROOT / "taskfiles/test/taskfile.yml").read_text()
        block = taskfile.split("  test:nix:\n", 1)[1].split("  test:powershell:\n", 1)[
            0
        ]
        self.assertEqual(block.count("nix build "), 1)
        self.assertCountEqual(
            re.findall(r"\.\#checks\.\$\{system\}\.([a-z-]+)", block),
            (
                "powershell-formatter",
                "nix-unit",
                "custom-package-builds",
                "aerospace-workspace-cycle",
                "docker-desktop-activation",
                "neovim-native",
                "ghostty-config",
            ),
        )
        self.assertIn("--no-write-lock-file", block)

    def test_consistency_nix_checks_share_one_logged_build(self) -> None:
        workflow = self._workflow_job(self._named_workflow("ci-nix.yml"), "check")
        commands = workflow.replace("\\\n", " ").splitlines()
        check_commands = [
            line for line in commands if "nix build " in line and ".#checks." in line
        ]
        self.assertEqual(len(check_commands), 1)
        for check in (
            "nix-unit",
            "custom-package-builds",
            "aerospace-workspace-cycle",
            "windows-keybindings-generated",
        ):
            self.assertIn(f".#checks.x86_64-linux.{check}", check_commands[0])
        self.assertIn("--print-build-logs", check_commands[0])

    def test_powershell_formatter_regression_runs_in_local_and_native_ci_routes(
        self,
    ) -> None:
        taskfile = (REPOSITORY_ROOT / "taskfiles/test/taskfile.yml").read_text()
        self.assertIn(".#checks.${system}.powershell-formatter", taskfile)
        bootstrap = self._named_workflow("ci-nix.yml")
        linux = self._workflow_job(bootstrap, "linux-build")
        self.assertNotIn("powershell-formatter", linux)
        self.assertIn(".#nixosConfigurations.linux.config.system.build.toplevel", linux)
        self.assertIn("darwin-rebuild -- switch", self._workflow_job(bootstrap, "darwin"))
        tools = self._workflow_job(bootstrap, "ci-tools")
        self.assertIn("check-bootstrap-ci-tools.sh --sandbox", tools)

    def test_workspace_cycle_runtime_check_runs_in_local_and_hosted_nix_jobs(
        self,
    ) -> None:
        taskfile = (REPOSITORY_ROOT / "taskfiles/test/taskfile.yml").read_text()
        self.assertIn(".#checks.${system}.aerospace-workspace-cycle", taskfile)
        consistency = self._named_workflow("ci-nix.yml")
        bootstrap = self._named_workflow("ci-nix.yml")
        self.assertIn(".#checks.x86_64-linux.aerospace-workspace-cycle", consistency)
        self.assertNotIn("aerospace-workspace-cycle", bootstrap)

    def test_generated_windows_keybindings_have_local_and_hosted_drift_checks(
        self,
    ) -> None:
        consistency = self._named_workflow("ci-nix.yml")
        self.assertIn(
            ".#checks.x86_64-linux.windows-keybindings-generated", consistency
        )
        taskfile = (REPOSITORY_ROOT / "taskfiles/test/taskfile.yml").read_text()
        self.assertIn("task: keybindings:check", taskfile)

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

    def test_pull_requests_to_main_always_run_ci_contract(self) -> None:
        workflow = self._workflow()
        self.assertIn("name: CI Contract", workflow)
        self.assertRegex(
            workflow,
            r"(?ms)^\s*pull_request:\n\s*branches: \[main\]\n(?!\s*paths:)",
        )
        self.assertRegex(workflow, r"(?m)^\s+name: CI Contract$")

    def test_push_always_reports_and_manual_runs_are_supported(self) -> None:
        workflow = self._workflow()
        triggers = workflow.split("env:", 1)[0]
        self.assertIn("workflow_dispatch:", triggers)
        self.assertIn("push:", triggers)
        self.assertIn("branches: [main]", triggers)
        self.assertNotIn("paths:", triggers)

    def test_ci_contract_lints_workflows_without_python_tests(self) -> None:
        workflow = self._workflow()
        self.assertIn(CHECKOUT_ACTION, workflow)
        self.assertNotIn("actions/setup-python", workflow)
        self.assertNotIn("tests/python", workflow)
        self.assertNotIn("install-nix-action", workflow)
        self.assertIn("actionlint", workflow)

    def test_ci_contract_does_not_install_test_only_tools(self) -> None:
        workflow = self._workflow()
        self.assertNotIn("nix profile install nixpkgs#go-task", workflow)
        self.assertNotIn("python -m unittest", workflow)
        self.assertIn("Run actionlint", workflow)

    def test_bash_contracts_have_one_preinstalled_linux_owner(self) -> None:
        workflow = self._named_workflow("ci-nix.yml")
        job = self._workflow_job(workflow, "bash-test")
        self.assertIn("runs-on: ubuntu-24.04", job)
        self.assertIn("container:", job)
        self.assertIn("bash scripts/sh/run-bash-tests.sh", job)
        self.assertIn("needs.changes.outputs.other == 'true'", job)
        self.assertNotIn("matrix:", job)
        self.assertNotIn("Install Nix", job)
        self.assertNotIn("Run Bash workflow contracts", self._workflow())
        self.assertNotIn("DOTFILES_USER", job)
        self.assertNotIn("DOTFILES_HOME", job)
        darwin = self._workflow_job(workflow, "darwin")
        self.assertNotIn("scripts/sh/run-bash-tests.sh", darwin)
        self.assertNotIn("brew install", darwin)
        self.assertNotIn("attestation", darwin)
        self.assertNotRegex(job, r"continue-on-error:\s*true")
        for section in (job, darwin):
            self.assertNotIn("DOTFILES_USER", section)
            self.assertNotIn("DOTFILES_HOME", section)

    def test_linux_build_leaves_identity_resolution_to_nix(
        self,
    ) -> None:
        workflow = self._named_workflow("ci-nix.yml")
        job = self._workflow_job(workflow, "linux-build")
        script = re.search(
            r"(?m)^      - name: Build Linux configurations and checks\n"
            r"        run: \|\n(?P<script>(?:          .*\n)+)",
            job,
        )
        self.assertIsNotNone(script)
        assert script is not None
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            getent = directory / "getent"
            getent.write_text(
                '#!/bin/bash\n[[ "$*" == "passwd node" ]] || exit 64\n'
                "printf '%s\\n' 'node:x:1000:1000::/home/node:/bin/bash'\n"
            )
            nix = directory / "nix"
            nix.write_text(
                f"#!{sys.executable}\n"
                "import json, os, sys\n"
                "print(json.dumps({'argv': sys.argv[1:], 'identity': "
                "{key: os.environ.get(key) for key in "
                "('DOTFILES_USER', 'DOTFILES_HOME')}}))\n"
            )
            getent.chmod(0o755)
            nix.chmod(0o755)
            environment = dict(os.environ)
            environment.update(
                PATH=f"{directory}:{environment['PATH']}", GITHUB_WORKSPACE=temporary
            )
            for variable in (
                "DOTFILES_USER",
                "DOTFILES_HOME",
            ):
                environment.pop(variable, None)
            result = subprocess.run(
                [
                    "bash",
                    "--noprofile",
                    "--norc",
                    "-e",
                    "-o",
                    "pipefail",
                    "-c",
                    textwrap.dedent(script.group("script")),
                ],
                env=environment,
                capture_output=True,
                text=True,
                check=True,
            )
        invocation = json.loads(result.stdout)
        self.assertEqual(invocation["argv"][:2], ["build", "--impure"])
        self.assertIn(".#nixosConfigurations.linux.config.system.build.toplevel", invocation["argv"])
        self.assertIn(".#homeConfigurations.x86_64-linux.activationPackage", invocation["argv"])
        self.assertEqual(
            invocation["identity"],
            {
                "DOTFILES_USER": None,
                "DOTFILES_HOME": None,
            },
        )
        for variable in (
            "DOTFILES_USER",
            "DOTFILES_HOME",
            "DOTFILES_UID",
            "DOTFILES_GID",
            "DOTFILES_GROUP",
        ):
            self.assertNotRegex(workflow, rf"(?m)^\s+{variable}:")
            self.assertNotIn(variable, workflow.replace(job, ""))

    def test_wsl_prebuild_exports_zstd_cache_and_fails_closed(self) -> None:
        workflow = self._named_workflow("ci-nix.yml")
        job = self._workflow_job(workflow, "wsl-prebuild")
        script = re.search(
            r"(?m)^        run: \|\n(?P<script>(?:          [^\n]*\n|\n)+)", job
        )
        self.assertIsNotNone(script)
        assert script is not None
        expected_paths = [
            f"/nix/store/{'b' * 32}-hermes",
        ]
        for copy_exit in (0, 47):
            with (
                self.subTest(copy_exit=copy_exit),
                tempfile.TemporaryDirectory() as temporary,
            ):
                directory = Path(temporary)
                runner_temp = directory / "container runner temp"
                runner_temp.mkdir()
                output = directory / "step-output"
                output.touch()
                nix = directory / "nix"
                nix.write_text(
                    f"#!{sys.executable}\n"
                    "import os, pathlib, sys\n"
                    "from urllib.parse import urlsplit, parse_qs\n"
                    f"paths = {expected_paths!r}\n"
                    "if sys.argv[1:] == ['--version']:\n"
                    "    print('nix boundary double')\n"
                    "elif sys.argv[1] == 'build':\n"
                    "    assert '.#nixosConfigurations.nixos.config.system.build.toplevel' in sys.argv\n"
                    "    print(paths[0])\n"
                    "elif sys.argv[1:3] == ['copy', '--to']:\n"
                    "    assert sys.argv[4:] == paths\n"
                    "    target = urlsplit(sys.argv[3])\n"
                    "    assert target.scheme == 'file' and not target.netloc\n"
                    "    assert parse_qs(target.query) == {'compression': ['zstd']}\n"
                    "    if os.environ['COPY_EXIT'] != '0': raise SystemExit(int(os.environ['COPY_EXIT']))\n"
                    "    pathlib.Path(target.path, 'cache-entry').write_text('cache')\n"
                    "else:\n"
                    "    raise SystemExit(64)\n"
                )
                nix.chmod(0o755)
                environment = dict(os.environ)
                environment.update(
                    PATH=f"{directory}:{environment['PATH']}",
                    RUNNER_TEMP=str(runner_temp),
                    GITHUB_OUTPUT=str(output),
                    COPY_EXIT=str(copy_exit),
                )
                result = subprocess.run(
                    [
                        "bash",
                        "--noprofile",
                        "--norc",
                        "-e",
                        "-o",
                        "pipefail",
                        "-c",
                        textwrap.dedent(script.group("script")),
                    ],
                    env=environment,
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(
                    result.returncode, copy_exit, result.stdout + result.stderr
                )
                if copy_exit:
                    self.assertEqual(
                        output.read_text(),
                        "",
                        "failed exports must not publish an artifact path",
                    )
                    self.assertFalse(
                        (
                            runner_temp / "wsl-nix-cache-artifact/wsl-nix-cache.tar"
                        ).exists()
                    )
                    continue
                self.assertTrue(
                    output.is_file(),
                    "prebuild must export its actual container artifact directory",
                )
                outputs = dict(
                    line.split("=", 1) for line in output.read_text().splitlines()
                )
                artifact = Path(outputs["artifact-dir"])
                self.assertTrue(artifact.is_relative_to(runner_temp))
                self.assertEqual(
                    sorted(path.name for path in artifact.iterdir()),
                    ["wsl-nix-cache.tar", "wsl-system-paths.txt"],
                )
                self.assertEqual(
                    (artifact / "wsl-system-paths.txt").read_text().splitlines(),
                    expected_paths,
                )
                with tarfile.open(artifact / "wsl-nix-cache.tar") as archive:
                    self.assertIn("./cache-entry", archive.getnames())
        self.assertIn("id: wsl-cache", job)
        self.assertIn("path: ${{ steps.wsl-cache.outputs.artifact-dir }}", job)
        self.assertNotIn("${{ runner.temp }}", job)

    def test_runs_actionlint_without_python_test_discovery(self) -> None:
        workflow = self._workflow()
        actionlint_lines = [
            line.strip()
            for line in workflow.splitlines()
            if "go run github.com/rhysd/actionlint" in line
        ]
        self.assertIn(
            "run: go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.12 "
            ".github/workflows/*.yml",
            actionlint_lines,
        )
        self.assertNotIn(
            "run: go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.12",
            actionlint_lines,
        )
        self.assertNotIn("python -m unittest", workflow)

    def test_ci_security_checks_cover_local_actions_and_pinned_devcontainer_tools(
        self,
    ) -> None:
        codeql = self._named_workflow("codeql.yml")
        self.assertEqual(codeql.count('      - ".github/actions/**"'), 2)

        devcontainer = self._named_workflow("ci-other.yml")
        self.assertNotRegex(devcontainer, r"(?m)^  macos:$")
        self.assertNotRegex(devcontainer, r"runs-on:\s+macos-")
        self.assertEqual(
            devcontainer.count(
                "npm install --global --no-audit --no-fund @devcontainers/cli@0.88.0"
            ),
            1,
        )
        self.assertNotIn("npm install -g @devcontainers/cli", devcontainer)
        linux = self._workflow_job(devcontainer, "linux-nix")
        self.assertIn("nix profile install 'nixpkgs#devcontainer'", linux)
        self.assertIn("--frozen-lockfile", linux)
        windows = self._workflow_job(devcontainer, "windows")
        self.assertIn("@devcontainers/cli@0.88.0", windows)

    def test_nix_build_jobs_use_authenticated_github_fetches(self) -> None:
        workflow = self._named_workflow("ci-nix.yml")
        for job_name in ("nix", "linux-build", "wsl-prebuild"):
            with self.subTest(job=job_name):
                job = self._workflow_job(workflow, job_name)
                self.assertIn("run: bash scripts/sh/configure-bootstrap-ci-nix.sh", job)
                self.assertIn(
                    "GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}",
                    job,
                )

        wsl_job = self._workflow_job(workflow, "wsl")
        self.assertIn("GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}", wsl_job)
        self.assertIn("WSLENV: GITHUB_TOKEN/u", wsl_job)

    def test_linux_hardware_fixture_uses_the_container_workspace(self) -> None:
        job = self._workflow_job(self._named_workflow("ci-nix.yml"), "linux-build")
        self.assertNotIn("${{ github.workspace }}/nix/tests/fixtures", job)
        self.assertIn(
            'export DOTFILES_NIXOS_HARDWARE_CONFIG="$GITHUB_WORKSPACE/nix/tests/fixtures/hardware-configuration.nix"',
            job,
        )

    def test_bootstrap_detects_dependencies_once_without_push_path_filters(
        self,
    ) -> None:
        workflow = self._named_workflow("ci-nix.yml")
        triggers = workflow.split("concurrency:", 1)[0]
        self.assertNotIn("paths:", triggers)
        changes = self._workflow_job(workflow, "changes")
        self.assertEqual(changes.count("uses: ./.github/actions/detect-ci-changes"), 1)
        self.assertNotIn("manifest:", changes)
        for category in ("nix", "chezmoi", "other"):
            self.assertIn(
                f"{category}: ${{{{ steps.detect.outputs.{category} }}}}", changes
            )

    def test_bootstrap_workflow_integrates_nix_and_winget_validation(self) -> None:
        workflow = self._named_workflow("ci-nix.yml")

        changes = self._workflow_job(workflow, "changes")
        self.assertIn("nix: ${{ steps.detect.outputs.nix }}", changes)

        for job_name, output in (
            ("nix", "nix"),
            ("windows-installer", "chezmoi"),
        ):
            job = self._workflow_job(workflow, job_name)
            self.assertIn(f"needs.changes.outputs.{output} == 'true'", job)

        self.assertIn("Bootstrap / Nix", workflow)
        self.assertIn("Bootstrap / Windows / Installer", workflow)

        complete = self._workflow_job(workflow, "complete")
        self.assertIn("NIX_REQUIRED", complete)
        self.assertIn("WINDOWS_INSTALLER_RESULT", complete)
        self.assertIn("NIX_RESULT: ${{ needs.nix.result }}", complete)
        self.assertIn("windows-installer", complete)
        self.assertIn("check_required_job", complete)

    def test_replaced_workflows_are_removed(self) -> None:
        for name in (
            "ci-bootstrap.yml",
            "ci-consistency.yml",
            "ci-powershell.yml",
            "ci-devcontainer.yml",
            "ci-contract.yml",
            "ci-winget.yml",
        ):
            self.assertFalse((WORKFLOWS_DIRECTORY / name).exists(), name)

    def test_bash_suites_no_longer_have_devcontainer_ownership(self) -> None:
        self.assertFalse(DEVCONTAINER_BATS_PATH.exists())
        workflow = self._named_workflow("ci-other.yml")
        for job in ("linux-nix", "windows"):
            self.assertNotIn(
                "scripts/sh/run-bash-tests.sh", self._workflow_job(workflow, job)
            )
        self.assertNotIn(".devcontainer/ci/bats.sh", workflow)

    def test_hermes_ci_keeps_shell_runtime_contract_without_python_tests(self) -> None:
        workflow = self._named_workflow("ci-nix.yml")
        hermes = self._workflow_job(workflow, "hermes-runtime-contracts")
        self.assertIn("docker/hermes-browser/tests/test_runtime_contract.sh", hermes)
        self.assertNotIn("python", hermes)
        self.assertNotIn("hermes-bootstrap-tests", hermes)
        self.assertNotIn("docker build", hermes)
        complete = self._workflow_job(workflow, "complete")
        self.assertIn("hermes-runtime-contracts,", complete)
        self.assertIn(
            "HERMES_RESULT: ${{ needs.hermes-runtime-contracts.result }}", complete
        )
        self.assertIn('"${HERMES_REQUIRED}" "${HERMES_RESULT}"', complete)

    def test_hermes_python_test_hook_and_task_are_removed(self) -> None:
        pre_commit = PRE_COMMIT_PATH.read_text(encoding="utf-8")
        taskfile = HERMES_TASKFILE_PATH.read_text(encoding="utf-8")
        self.assertNotIn("hermes-bootstrap-tests", pre_commit)
        self.assertNotIn("hermes:bootstrap:test:", taskfile)
        self.assertNotIn("test_xapi_image_contract.py", taskfile)

    def test_unified_bootstrap_workflow_keeps_all_platform_jobs(self) -> None:
        workflow = self._named_workflow("ci-nix.yml")
        for job in (
            "nix",
            "linux-build",
            "darwin",
            "wsl-prebuild",
            "wsl",
            "windows",
            "windows-installer",
            "check",
            "complete",
        ):
            self._workflow_job(workflow, job)
        self.assertIn("name: Bootstrap CI", workflow)
        self.assertIn("runs-on: macos-15", self._workflow_job(workflow, "darwin"))
        self.assertNotIn("macos-13", workflow)

    def test_unified_bootstrap_workflow_fails_closed_for_selected_platforms(
        self,
    ) -> None:
        workflow = self._named_workflow("ci-nix.yml")

        changes = self._workflow_job(workflow, "changes")
        for category in ("nix", "chezmoi", "other"):
            self.assertIn(f"{category}:", changes)

        complete = self._workflow_job(workflow, "complete")
        self.assertIn("PLATFORM_REQUIRED", complete)
        self.assertIn("LINUX_BUILD_REQUIRED", complete)
        self.assertIn("WSL_REQUIRED", complete)
        self.assertIn("WSL_PREBUILD_RESULT", complete)
        self.assertIn('check_required_job "WSL / Prebuild"', complete)
        self.assertNotIn("check_platform", complete)
        self.assertNotIn("success|skipped", complete)

        for job_name in (
            "linux-build",
            "darwin",
            "wsl-prebuild",
            "wsl",
            "windows",
        ):
            job = self._workflow_job(workflow, job_name)
            self.assertIn("ref: ${{ env.TESTED_SHA }}", job)

    def test_bootstrap_checks_out_the_pull_request_head_sha(self) -> None:
        workflow = self._named_workflow("ci-nix.yml")

        self.assertIn(
            "group: bootstrap-${{ github.workflow }}-${{ github.ref }}",
            workflow,
        )
        self.assertIn("cancel-in-progress: true", workflow)
        self.assertIn(
            "TESTED_SHA: ${{ github.event_name == 'pull_request' && "
            "github.event.pull_request.head.sha || github.sha }}",
            workflow,
        )

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
            ("      - run: >-\n          Invoke-Pester -Path .\\tests\\CHEZMOI"),
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
        self.assertRegex(
            font_install, r"(?m)^    name: Font install smoke \(Windows\)$"
        )

        self.assertRegex(
            lint,
            r"(?ms)^      - name: Upload test results\n"
            r"        uses: actions/upload-artifact@[0-9a-f]{40}.*?\n"
            r"        if: always\(\)\n"
            r"        with:\n"
            r"          name: chezmoi-test-results\n"
            r"          path: scripts/powershell/chezmoi-test-results\.xml$",
        )

    def test_home_readme_distinguishes_supported_systems_from_ci_build_routes(
        self,
    ) -> None:
        readme = (REPOSITORY_ROOT / "nix" / "tests" / "README.md").read_text(
            encoding="utf-8"
        )
        workflow = self._named_workflow("ci-nix.yml")
        nix_test = self._workflow_job(workflow, "check")
        darwin = self._workflow_job(workflow, "darwin")
        normalized_readme = " ".join(readme.split())

        self.assertNotIn(
            "`x86_64-linux` / `aarch64-linux` の CI runner で実行します。",
            normalized_readme,
        )
        for system in ("x86_64-linux", "aarch64-linux", "aarch64-darwin"):
            self.assertIn(f"`{system}`", readme)

        self.assertIn(
            "`aarch64-linux` は flake の support/output には含まれますが、"
            "この workflow には ARM64 Linux runner の native build がありません。",
            normalized_readme,
        )
        self.assertNotIn(
            "nix build .#checks.aarch64-linux.nix-unit",
            workflow,
        )

        for runner, job in (
            ("ubuntu-24.04", self._workflow_job(workflow, "linux-build")),
            ("macos-15", darwin),
        ):
            self.assertIn(f"`{runner}`", readme)
            self.assertIn(f"runs-on: {runner}", job)

        for target, job in (
            (".#checks.x86_64-linux.nix-unit", nix_test),
            (".#checks.x86_64-linux.custom-package-builds", nix_test),
            (".#checks.aarch64-darwin.nix-unit", darwin),
            (".#checks.aarch64-darwin.custom-package-builds", darwin),
        ):
            self.assertIn(target, readme)
            self.assertIn(target, job)


if __name__ == "__main__":
    unittest.main()
