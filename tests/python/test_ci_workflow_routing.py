"""Contract tests for the lightweight CI routing workflow."""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tarfile
import tempfile
import textwrap
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
WORKFLOW_PATH = REPOSITORY_ROOT / ".github" / "workflows" / "ci-contract.yml"
WORKFLOWS_DIRECTORY = WORKFLOW_PATH.parent
PRE_COMMIT_PATH = REPOSITORY_ROOT / ".pre-commit-config.yaml"
DEVCONTAINER_BATS_PATH = REPOSITORY_ROOT / ".devcontainer" / "ci" / "bats.sh"
HERMES_TASKFILE_PATH = REPOSITORY_ROOT / "taskfiles" / "hermes" / "taskfile.yml"
CHEZMOI_WORKFLOW = "ci-chezmoi.yml"
CHECKOUT_ACTION = "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"
SETUP_PYTHON_ACTION = "actions/setup-python@5fda3b95a4ea91299a34e894583c3862153e4b97"
INSTALL_NIX_ACTION = "cachix/install-nix-action@13d8dd58da0234aa297dedd986986ccb8e7f3e24"


class CiWorkflowRoutingContractTests(unittest.TestCase):
    """Keep the lightweight CI workflow's trigger and tool contracts stable."""

    def test_workspace_cycle_runtime_check_runs_in_local_and_hosted_nix_jobs(self) -> None:
        taskfile = (REPOSITORY_ROOT / "taskfiles/test/taskfile.yml").read_text()
        self.assertIn('.#checks.${system}.aerospace-workspace-cycle', taskfile)
        consistency = self._named_workflow("ci-consistency.yml")
        bootstrap = self._named_workflow("ci-bootstrap.yml")
        self.assertIn('.#checks.x86_64-linux.aerospace-workspace-cycle', consistency)
        for system in ("x86_64-linux", "aarch64-darwin"):
            self.assertIn(f'.#checks.{system}.aerospace-workspace-cycle', bootstrap)

    def test_generated_windows_keybindings_have_local_and_hosted_drift_checks(self) -> None:
        consistency = self._named_workflow("ci-consistency.yml")
        self.assertIn(".#checks.x86_64-linux.windows-keybindings-generated", consistency)
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

    def _trigger_paths(self, workflow: str, event: str) -> str:
        match = re.search(
            rf"(?ms)^  {re.escape(event)}:\n"
            r"\s+branches: \[main\]\n"
            r"\s+paths:\n(?P<paths>.*?)(?=^  (?:push|pull_request):|^concurrency:|^permissions:)",
            workflow,
        )
        self.assertIsNotNone(match, f"missing {event} path filter")
        return match.group("paths") if match is not None else ""

    def _job_patterns(self, output: str) -> list[str]:
        manifest = json.loads((REPOSITORY_ROOT / "ci/job-path-routing.json").read_text())
        return [pattern for rule in manifest["rules"] if output in rule["outputs"]
                for pattern in rule["patterns"]]

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
            "nix/**/*.md",
            "docs/mlflow/**",
            "taskfiles/mlflow/**",
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

    def test_installs_go_task_before_running_taskfile_contracts(self) -> None:
        workflow = self._workflow()
        install_position = workflow.find("nix profile install nixpkgs#go-task")
        contract_position = workflow.find("python -m unittest discover -s tests/python -v")

        self.assertGreaterEqual(install_position, 0)
        self.assertGreater(contract_position, install_position)
        self.assertIn("task --version", workflow[install_position:contract_position])

    def test_bash_contracts_have_one_preinstalled_linux_owner(self) -> None:
        workflow = self._named_workflow("ci-bootstrap.yml")
        job = self._workflow_job(workflow, "bash-test")
        self.assertIn("runs-on: ubuntu-24.04", job)
        self.assertIn("container:", job)
        self.assertIn("bash scripts/sh/run-bash-tests.sh", job)
        self.assertIn("needs.changes.outputs.bash == 'true'", job)
        self.assertNotIn("matrix:", job)
        self.assertNotIn("Install Nix", job)
        self.assertNotIn("Run Bash workflow contracts", self._workflow())
        self.assertNotIn("DOTFILES_USER", job)
        self.assertNotIn("DOTFILES_HOME", job)
        darwin = self._workflow_job(workflow, "darwin")
        self.assertNotIn("bats", darwin)
        self.assertNotIn("brew install", darwin)
        self.assertNotIn("attestation", darwin)
        for section in (job, darwin):
            self.assertNotIn("DOTFILES_USER", section)
            self.assertNotIn("DOTFILES_HOME", section)

    def test_linux_build_uses_image_identity_for_both_system_manager_outputs(self) -> None:
        workflow = self._named_workflow("ci-bootstrap.yml")
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
            identity = directory / "id"
            identity.write_text(
                '#!/bin/bash\n[[ "$*" == "-gn node" ]] || exit 64\n'
                "printf '%s\\n' node\n"
            )
            nix = directory / "nix"
            nix.write_text(
                f"#!{sys.executable}\n"
                "import json, os, sys\n"
                "print(json.dumps({'argv': sys.argv[1:], 'identity': "
                "{key: os.environ.get(key) for key in "
                "('DOTFILES_USER', 'DOTFILES_HOME', 'DOTFILES_UID', 'DOTFILES_GID', 'DOTFILES_GROUP')}}))\n"
            )
            getent.chmod(0o755)
            identity.chmod(0o755)
            nix.chmod(0o755)
            environment = dict(os.environ)
            environment.update(PATH=f"{directory}:{environment['PATH']}", GITHUB_WORKSPACE=temporary)
            for variable in ("DOTFILES_USER", "DOTFILES_HOME", "DOTFILES_UID", "DOTFILES_GID", "DOTFILES_GROUP"):
                environment.pop(variable, None)
            result = subprocess.run(
                ["bash", "--noprofile", "--norc", "-e", "-o", "pipefail", "-c", textwrap.dedent(script.group("script"))],
                env=environment,
                capture_output=True,
                text=True,
                check=True,
            )
        invocation = json.loads(result.stdout)
        self.assertEqual(invocation["argv"][:2], ["build", "--impure"])
        self.assertIn(".#systemConfigs.ubuntu", invocation["argv"])
        self.assertIn(".#systemConfigs.debian", invocation["argv"])
        self.assertEqual(invocation["identity"], {
            "DOTFILES_USER": "node",
            "DOTFILES_HOME": "/home/node",
            "DOTFILES_UID": "1000",
            "DOTFILES_GID": "1000",
            "DOTFILES_GROUP": "node",
        })
        for variable in ("DOTFILES_USER", "DOTFILES_HOME", "DOTFILES_UID", "DOTFILES_GID", "DOTFILES_GROUP"):
            self.assertNotRegex(workflow, rf"(?m)^\s+{variable}:")
            self.assertNotIn(variable, workflow.replace(job, ""))

    def test_wsl_prebuild_exports_a_directory_with_both_consumer_files(self) -> None:
        workflow = self._named_workflow("ci-bootstrap.yml")
        job = self._workflow_job(workflow, "wsl-prebuild")
        script = re.search(r"(?m)^        run: \|\n(?P<script>(?:          [^\n]*\n|\n)+)", job)
        self.assertIsNotNone(script)
        assert script is not None
        expected_paths = [f"/nix/store/{'a' * 32}-base", f"/nix/store/{'b' * 32}-hermes"]
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            runner_temp = directory / "container runner temp"
            runner_temp.mkdir()
            output = directory / "step-output"
            nix = directory / "nix"
            nix.write_text(
                f"#!{sys.executable}\n"
                "import os, pathlib, sys\n"
                f"paths = {expected_paths!r}\n"
                "if sys.argv[1] == 'build':\n"
                "    assert '.#nixosConfigurations.nixos.config.system.build.toplevel' in sys.argv\n"
                "    print(paths[bool(os.environ.get('DOTFILES_WITH_HERMES'))])\n"
                "elif sys.argv[1:3] == ['copy', '--to']:\n"
                "    assert sys.argv[4:] == paths\n"
                "    pathlib.Path(sys.argv[3].removeprefix('file://'), 'cache-entry').write_text('cache')\n"
                "else:\n"
                "    raise SystemExit(64)\n"
            )
            nix.chmod(0o755)
            environment = dict(os.environ)
            environment.update(PATH=f"{directory}:{environment['PATH']}", RUNNER_TEMP=str(runner_temp), GITHUB_OUTPUT=str(output))
            environment.pop("DOTFILES_WITH_HERMES", None)
            subprocess.run(
                ["bash", "--noprofile", "--norc", "-e", "-o", "pipefail", "-c", textwrap.dedent(script.group("script"))],
                env=environment,
                capture_output=True,
                text=True,
                check=True,
            )
            self.assertTrue(output.is_file(), "prebuild must export its actual container artifact directory")
            outputs = dict(line.split("=", 1) for line in output.read_text().splitlines())
            artifact = Path(outputs["artifact-dir"])
            self.assertTrue(artifact.is_relative_to(runner_temp))
            self.assertEqual(sorted(path.name for path in artifact.iterdir()), ["wsl-nix-cache.tar", "wsl-system-paths.txt"])
            self.assertEqual((artifact / "wsl-system-paths.txt").read_text().splitlines(), expected_paths)
            with tarfile.open(artifact / "wsl-nix-cache.tar") as archive:
                self.assertIn("./cache-entry", archive.getnames())
        self.assertIn("id: wsl-cache", job)
        self.assertIn("path: ${{ steps.wsl-cache.outputs.artifact-dir }}", job)
        self.assertNotIn("${{ runner.temp }}", job)

    def test_runs_focused_actionlint_and_python_discovery(self) -> None:
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
        self.assertIn("python -m unittest discover -s tests/python -v", workflow)

    def test_ci_security_checks_cover_local_actions_and_pinned_devcontainer_tools(
        self,
    ) -> None:
        codeql = self._named_workflow("codeql.yml")
        self.assertEqual(codeql.count('      - ".github/actions/**"'), 2)

        devcontainer = self._named_workflow("ci-devcontainer.yml")
        self.assertRegex(
            devcontainer,
            r"(?m)^\s*uses: docker/setup-docker-action@[0-9a-f]{40}(?:\s+#.*)?\s*$",
        )
        self.assertEqual(
            devcontainer.count(
                "npm install --global --no-audit --no-fund @devcontainers/cli@0.88.0"
            ),
            2,
        )
        self.assertNotIn("npm install -g @devcontainers/cli", devcontainer)

    def test_nix_build_jobs_use_authenticated_github_fetches(self) -> None:
        workflow = self._named_workflow("ci-bootstrap.yml")
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
        job = self._workflow_job(self._named_workflow("ci-bootstrap.yml"), "linux-build")
        self.assertNotIn("${{ github.workspace }}/nix/tests/fixtures", job)
        self.assertIn(
            'export DOTFILES_NIXOS_HARDWARE_CONFIG="$GITHUB_WORKSPACE/nix/tests/fixtures/hardware-configuration.nix"',
            job,
        )
    def test_bootstrap_detects_dependencies_without_push_path_filters(self) -> None:
        workflow = self._named_workflow("ci-bootstrap.yml")
        push = workflow.split("  push:\n", 1)[1].split("  pull_request:\n", 1)[0]
        self.assertIn("branches: [main]", push)
        self.assertNotIn("paths:", push)
        changes = self._workflow_job(workflow, "changes")
        self.assertIn("manifest: ci/bootstrap-path-routing.json", changes)
        self.assertIn("manifest: ci/job-path-routing.json", changes)


    def test_contract_workflow_runs_the_dedicated_mlflow_gateway_tests(self) -> None:
        workflow = self._workflow()
        push_paths = self._trigger_paths(workflow, "push")

        self.assertIn('"docker/mlflow/**"', push_paths)
        self.assertIn('"docker/local-ai-services/**"', push_paths)
        self.assertIn(
            "python -m unittest docker/mlflow/tests/test_configure.py -v",
            workflow,
        )

    def test_bootstrap_workflow_integrates_nix_and_winget_validation(self) -> None:
        workflow = self._named_workflow("ci-bootstrap.yml")

        changes = self._workflow_job(workflow, "changes")
        self.assertIn("nix: ${{ steps.detect.outputs.nix }}", changes)

        for job_name, output in (
            ("nix", "nix"),
            ("windows-installer", "windows"),
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


    def test_legacy_nix_and_winget_workflows_are_removed(self) -> None:
        for name in ("ci-nix.yml", "ci-winget.yml"):
            self.assertFalse((WORKFLOWS_DIRECTORY / name).exists(), name)

    def test_darwin_provider_update_workflow_is_pinned_and_safe(self) -> None:
        workflow = self._named_workflow("update-darwin-packages.yml")

        self.assertIn("name: Darwin package updates", workflow)
        self.assertIn("runs-on: macos-26", workflow)
        self.assertIn("workflow_dispatch:", workflow)
        self.assertIn("schedule:", workflow)
        self.assertNotIn("pull_request_target", workflow)
        self.assertIn("persist-credentials: false", workflow)
        self.assertIn("task darwin:update:check", workflow)
        self.assertIn("task darwin:update:promote", workflow)
        self.assertIn("nix build", workflow)
        self.assertIn("gh pr create", workflow)
        self.assertIn("matrix", workflow)

        validate = self._workflow_job(workflow, "validate")
        self.assertIn("GH_TOKEN: ${{ github.token }}", validate)

        for action in re.findall(r"uses:\s+([^\s]+)", workflow):
            self.assertRegex(action, r"@[0-9a-f]{40}$", action)

        complete = self._workflow_job(workflow, "complete")
        self.assertIn("if: ${{ always() }}", complete)
        self.assertIn("needs:", complete)

    def _scoped_workflow_mapping(self, lines: list[str], indent: int) -> dict:
        """Read this job's plain scalar mappings; reject other YAML forms."""
        mapping = {}
        levels = [(indent, mapping)]
        for line in lines:
            if not line.strip():
                continue
            field = re.fullmatch(r"( *)([A-Za-z][A-Za-z0-9_-]*):(?: (.+))?", line)
            self.assertIsNotNone(field, f"unsupported scoped workflow field: {line}")
            spaces, key, value = field.groups()
            while len(spaces) < levels[-1][0] and len(levels) > 1:
                levels.pop()
            self.assertEqual(len(spaces), levels[-1][0], f"unexpected indent: {line}")
            current = levels[-1][1]
            self.assertNotIn(key, current, f"duplicate scoped workflow field: {key}")
            if value is None:
                current[key] = {}
                levels.append((len(spaces) + 2, current[key]))
            else:
                self.assertFalse(
                    value != value.strip()
                    or value.startswith(("'", '"', "|", ">", "[", "{", "&", "*", "!"))
                    or re.search(r"\s#", value),
                    f"unsupported scoped workflow scalar: {line}",
                )
                current[key] = value
        return mapping

    def _darwin_validate_job(self, workflow: str) -> dict:
        self.assertEqual(len(re.findall(r"(?m)^  validate:\s*$", workflow)), 1)
        job = self._workflow_job(workflow, "validate")
        fields, separator, steps = job.partition("    steps:\n")
        self.assertTrue(separator, "missing validate steps")
        validate = self._scoped_workflow_mapping(fields.splitlines(), 4)
        step_blocks = re.split(r"(?m)^      - ", steps)
        self.assertFalse(step_blocks[0].strip(), "unexpected validate steps content")
        validate["steps"] = [
            self._scoped_workflow_mapping(
                ("        " + block).splitlines(), 8
            )
            for block in step_blocks[1:]
        ]
        return validate

    def _assert_darwin_validate_event_head(self, workflow: str) -> None:
        validate = self._darwin_validate_job(workflow)
        checkouts = [
            step for step in validate["steps"]
            if step.get("uses", "").startswith("actions/checkout@")
        ]
        self.assertEqual(len(checkouts), 1, "validate must have one source checkout")
        checkout = checkouts[0]
        inputs = checkout.get("with", {})
        self.assertIn("ref", inputs, "validate checkout must explicitly pin its ref")
        self.assertEqual(inputs["ref"], "${{ env.TESTED_SHA }}")
        self.assertEqual(
            validate.get("env"),
            {
                "GH_TOKEN": "${{ github.token }}",
                "TESTED_SHA": "${{ github.event_name == 'pull_request' && "
                "github.event.pull_request.head.sha || github.sha }}",
            },
        )
        self.assertNotIn("TESTED_SHA", checkout.get("env", {}))
        self.assertEqual(checkout["uses"], CHECKOUT_ACTION)
        self.assertEqual(inputs.get("persist-credentials"), "false")
        self.assertEqual(validate.get("permissions"), {"contents": "read"})
        self.assertEqual(
            validate.get("if"),
            "github.event_name == 'push' || github.event_name == 'pull_request'",
        )

    def test_darwin_validate_checkout_pins_the_immutable_event_head(self) -> None:
        self._assert_darwin_validate_event_head(
            self._named_workflow("update-darwin-packages.yml")
        )

    def test_darwin_validate_rejects_missing_mutable_or_ambiguous_head_pins(self) -> None:
        workflow = self._named_workflow("update-darwin-packages.yml")
        self._assert_darwin_validate_event_head(workflow)
        ref = "          ref: ${{ env.TESTED_SHA }}\n"
        tested_sha = (
            "      TESTED_SHA: ${{ github.event_name == 'pull_request' && "
            "github.event.pull_request.head.sha || github.sha }}\n"
        )
        checkout = (
            "      - name: Checkout repository\n"
            f"        uses: {CHECKOUT_ACTION}\n"
            "        with:\n"
            f"{ref}"
            "          persist-credentials: false\n"
        )
        mutations = (
            ("missing ref", ref, ""),
            ("merge SHA for PR", ref, "          ref: ${{ github.sha }}\n"),
            ("mutable branch", ref, "          ref: main\n"),
            ("mutable PR branch", ref, "          ref: ${{ github.head_ref }}\n"),
            ("wrong env reference", ref, "          ref: ${{ env.OTHER_SHA }}\n"),
            ("missing job env", tested_sha, ""),
            (
                "wrong env expression", tested_sha,
                "      TESTED_SHA: ${{ github.sha }}\n",
            ),
            (
                "mutable env expression", tested_sha,
                tested_sha.replace("head.sha", "head.ref"),
            ),
            ("duplicate checkout", checkout, checkout + "\n" + checkout),
            (
                "duplicate checkout with extra scalar whitespace",
                "      - name: Install Nix\n",
                "      - name: Hidden mutable checkout\n"
                f"        uses:  {CHECKOUT_ACTION}\n"
                "        with:\n"
                "          ref: main\n\n"
                "      - name: Install Nix\n",
            ),
            ("duplicate ref", ref, ref + ref),
            ("duplicate env key", tested_sha, tested_sha + tested_sha),
            (
                "checkout shadows job env", checkout,
                checkout + "        env:\n          TESTED_SHA: main\n",
            ),
            ("commented scalar", ref, ref.rstrip() + " # hidden alternate ref\n"),
            ("quoted scalar", ref, "          ref: '${{ env.TESTED_SHA }}'\n"),
        )
        for name, before, after in mutations:
            with self.subTest(mutation=name):
                self.assertIn(before, workflow)
                mutated = workflow.replace(before, after, 1)
                self.assertNotEqual(mutated, workflow)
                with self.assertRaises(AssertionError):
                    self._assert_darwin_validate_event_head(mutated)

    def test_darwin_update_paths_route_to_darwin_nix_contract_and_catalog(self) -> None:
        for path in (
            "nix/packages/darwin-provider-candidates.nix",
            "scripts/python/update_darwin_packages.py",
            "tests/python/test_update_darwin_packages.py",
            ".github/workflows/update-darwin-packages.yml",
        ):
            with self.subTest(path=path):
                routed = self._route(path)
                for output in ("darwin", "nix", "contract", "package_catalog"):
                    self.assertTrue(routed[output], f"{path} did not route {output}")

    def _route(self, path: str) -> dict[str, bool]:
        import json
        import subprocess

        result = subprocess.run(
            [
                sys.executable,
                str(REPOSITORY_ROOT / "scripts/python/detect_ci_changes.py"),
                "--paths-file",
                "-",
            ],
            input=path + "\n",
            text=True,
            capture_output=True,
            check=True,
        )
        return json.loads(result.stdout)

    def test_bash_suites_no_longer_have_devcontainer_ownership(self) -> None:
        self.assertFalse(DEVCONTAINER_BATS_PATH.exists())
        self.assertNotIn(".devcontainer/ci/bats.sh", self._named_workflow("ci-devcontainer.yml"))
        paths = self._job_patterns("devcontainer")
        self.assertIn("scripts/sh/dcnvim.sh", paths)
        self.assertNotIn("tests/bash/install_macos.bats", paths)
        self.assertNotIn("tests/bash/install_linux.bats", paths)
        self.assertNotIn("tests/bash/**", paths)

    def test_hermes_ci_routes_xapi_contract_and_platform_adapters(self) -> None:
        workflow = self._named_workflow("ci-hermes-bootstrap.yml")
        required_paths = (
            "scripts/python/hermes_bootstrap/**",
            "tests/python/hermes_bootstrap_test/**",
            "nix/home/hermes-agent/**",
            "nix/home/hermes-agent.nix",
            "docker/hermes-service/**",
            "docker/hermes-browser/**",
            "docker/hermes-browser-mcp/**",
            "docker/hermes-xapi-mcp/**",
            "docker/hindsight/**",
            "docker/local-ai-services/**",
            "scripts/sh/hermes-*.sh",
            "scripts/powershell/handlers/Handler.HermesAgent.ps1",
            "tests/python/test_xapi_image_contract.py",
            ".github/workflows/ci-hermes-provenance.yml",
        )

        paths = self._job_patterns("hermes")
        for required_path in required_paths:
            self.assertIn(required_path, paths)
        self.assertIn(
            "python3 -m unittest tests/python/test_xapi_image_contract.py -v",
            workflow,
        )
        self.assertIn(
            "nix build .#checks.x86_64-linux.hermes-bootstrap-tests",
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
            "scripts/python/hermes_bootstrap/app.py",
            "tests/python/hermes_bootstrap_test/test_app.py",
            "nix/home/hermes-agent.nix",
            "docker/hermes-xapi-mcp/Dockerfile",
            "docker/local-ai-services/compose.yml",
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
            "Bootstrap / Linux / E2E / NixOS",
            "Bootstrap / Darwin",
            "Bootstrap / WSL / Prebuild",
            "Bootstrap / WSL",
            "Bootstrap / Windows",
            "Bootstrap / Complete",
        ):
            self.assertIn(marker, workflow)

        for job_name, output in (
            ("linux-build", "linux"),
            ("darwin", "darwin"),
            ("windows", "windows"),
        ):
            job = self._workflow_job(workflow, job_name)
            expected_needs = (
                "needs: [changes, ci-tools]"
                if job_name == "linux-build"
                else "needs: changes"
            )
            self.assertIn(expected_needs, job)
            self.assertIn(f"needs.changes.outputs.{output} == 'true'", job)

        wsl_prebuild = self._workflow_job(workflow, "wsl-prebuild")
        self.assertIn("needs: [changes, ci-tools]", wsl_prebuild)
        self.assertIn("needs.changes.outputs.wsl == 'true'", wsl_prebuild)
        self.assertIn("ref: ${{ env.TESTED_SHA }}", wsl_prebuild)
        wsl = self._workflow_job(workflow, "wsl")
        self.assertIn("needs: [changes, wsl-prebuild]", wsl)

        for job_name in ("linux-nixos",):
            job = self._workflow_job(workflow, job_name)
            self.assertIn("needs: [changes, linux-build]", job)
            self.assertIn("needs.changes.outputs.linux == 'true'", job)

        complete = self._workflow_job(workflow, "complete")
        self.assertIn("if: ${{ always() }}", complete)
        self.assertNotIn("success|skipped", complete)

    def test_unified_bootstrap_workflow_fails_closed_for_selected_platforms(self) -> None:
        workflow = self._named_workflow("ci-bootstrap.yml")


        changes = self._workflow_job(workflow, "changes")
        self.assertIn("platforms:", changes)

        complete = self._workflow_job(workflow, "complete")
        self.assertIn("PLATFORM_REQUIRED", complete)
        self.assertIn("LINUX_REQUIRED", complete)
        self.assertIn("WSL_REQUIRED", complete)
        self.assertIn("WSL_PREBUILD_RESULT", complete)
        self.assertIn('check_required_job "WSL / Prebuild"', complete)
        self.assertIn("check_platform", complete)
        self.assertNotIn("success|skipped", complete)

        for job_name in (
            "linux-build",
            "linux-nixos",
            "darwin",
            "wsl-prebuild",
            "wsl",
            "windows",
        ):
            job = self._workflow_job(workflow, job_name)
            self.assertIn("ref: ${{ env.TESTED_SHA }}", job)

    def test_bootstrap_checks_out_the_pull_request_head_sha(self) -> None:
        workflow = self._named_workflow("ci-bootstrap.yml")

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
            (
                "      - run: >-\n"
                "          Invoke-Pester -Path .\\tests\\CHEZMOI"
            ),
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


    def test_home_readme_distinguishes_supported_systems_from_ci_build_routes(
        self,
    ) -> None:
        readme = (
            REPOSITORY_ROOT / "nix" / "tests" / "README.md"
        ).read_text(encoding="utf-8")
        workflow = self._named_workflow("ci-bootstrap.yml")
        nix_test = self._workflow_job(workflow, "linux-build")
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
            ("ubuntu-24.04", nix_test),
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
