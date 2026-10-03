"""Exercise the registry selection scripts without publishing an image."""

from __future__ import annotations

import os
import re
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/ci-bootstrap.yml"


class BootstrapCiImageTests(unittest.TestCase):
    def test_nix_runs_statix_directly_without_sarif_permissions(self) -> None:
        workflow = (ROOT / ".github/workflows/ci-bootstrap.yml").read_text()
        lint_job = workflow.split("  nix:\n", 1)[1].split("  linux-build:\n", 1)[0]
        self.assertIn("run: statix check .", lint_job)
        self.assertNotIn("security-events:", lint_job)
        self.assertNotIn("SARIF", lint_job)

    def test_tool_image_changes_trigger_contract_checks_on_push(self) -> None:
        workflow = (ROOT / ".github/workflows/ci-contract.yml").read_text()
        push_paths = workflow.split("  push:\n", 1)[1].split("permissions:\n", 1)[0]
        self.assertIn('"docker/bootstrap-ci-tools/**"', push_paths)

    def test_authentication_uses_nix_config_home_and_keeps_tokens_private(self) -> None:
        for use_xdg, owned_home in ((True, True), (True, False), (False, True), (False, False)):
            with self.subTest(use_xdg=use_xdg, owned_home=owned_home), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                home = root / "passwd-home"
                home.mkdir()
                config = root / "xdg" if use_xdg else home / ".config"
                tools = root / "bin"
                tools.mkdir()
                commands = {
                    "getent": '#!/bin/bash\nprintf "fixture:x:0:0:Fixture:%s:/bin/bash\\n" "$FALLBACK_HOME"\n',
                    "nix": '#!/bin/bash\n[[ "$*" == "config show access-tokens" ]] || exit 64\ngrep "^access-tokens = " "$EXPECTED_CONFIG/nix/bootstrap-ci.conf" | cut -d= -f2-\n',
                }
                for name, content in commands.items():
                    command = tools / name
                    command.write_text(content)
                    command.chmod(0o755)
                environment = {
                    key: value
                    for key, value in os.environ.items()
                    if key not in ("XDG_CONFIG_HOME", "NIX_CONFIG", "NIX_USER_CONF_FILES")
                }
                environment.update(
                    HOME=str(home if owned_home else root / "missing-home"),
                    FALLBACK_HOME=str(home),
                    EXPECTED_CONFIG=str(config),
                    GITHUB_TOKEN="fixture-token-not-a-real-secret",
                    PATH=f"{tools}{os.pathsep}{os.environ['PATH']}",
                )
                if use_xdg:
                    environment["XDG_CONFIG_HOME"] = str(config)
                script = ROOT / "scripts/sh/configure-bootstrap-ci-nix.sh"
                for _ in range(2):
                    result = subprocess.run(
                        ["bash", str(script)],
                        env=environment,
                        text=True,
                        capture_output=True,
                        check=False,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertNotIn(environment["GITHUB_TOKEN"], result.stdout + result.stderr)
                secret_file = config / "nix/bootstrap-ci.conf"
                self.assertEqual(secret_file.stat().st_mode & 0o777, 0o600)
                self.assertEqual(
                    (config / "nix/nix.conf").read_text().count(f"include {secret_file}"),
                    1,
                )
                trusted_repositories = subprocess.run(
                    ["git", "config", "--file", str(home / ".gitconfig"), "--get-all", "safe.directory"],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(trusted_repositories.stdout.splitlines(), [str(ROOT)])
                self.assertNotIn(environment["GITHUB_TOKEN"], (home / ".gitconfig").read_text())

    def run_step(
        self, name: str, *, docker_exit: int = 0, **environment: str
    ) -> tuple[subprocess.CompletedProcess[str], str]:
        workflow = WORKFLOW.read_text()
        step = re.search(
            rf"(?ms)^      - name: {re.escape(name)}\n"
            r"(?P<body>.*?)(?=^      - name:|^  [\w-]+:|\Z)",
            workflow,
        )
        self.assertIsNotNone(step)
        assert step is not None
        script = textwrap.dedent(step.group("body").split("        run: |\n", 1)[1])
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            docker = root / "docker"
            docker.write_text(
                '#!/bin/bash\nset -euo pipefail\n'
                '[[ "$1 $2 $3" == "buildx imagetools inspect" ]]\n'
                'printf "%s\\n" "$DOCKER_RESULT"\n'
                'exit "$DOCKER_EXIT"\n'
            )
            docker.chmod(0o755)
            output = root / "output"
            result = subprocess.run(
                ["bash", "-c", script],
                capture_output=True,
                text=True,
                check=False,
                env={
                    **os.environ,
                    "PATH": f"{root}{os.pathsep}{os.environ['PATH']}",
                    "GITHUB_OUTPUT": str(output),
                    "GITHUB_REPOSITORY": "RuruSasu/Dotfiles",
                    "DEFINITION_HASH": "a" * 64,
                    "CAN_PUBLISH": "true",
                    "DOCKER_EXIT": str(docker_exit),
                    "DOCKER_RESULT": "sha256:" + "b" * 64,
                    **environment,
                },
            )
            return result, output.read_text() if output.exists() else ""

    def test_existing_image_is_reused_without_a_build(self) -> None:
        result, output = self.run_step("Select image for the tool definition")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            output,
            f"tag=ghcr.io/rurusasu/dotfiles/bootstrap-ci-tools:{'a' * 64}\nbuild=false\n",
        )

    def test_missing_image_is_built_only_with_publish_authority(self) -> None:
        for can_publish, expected_exit in (("true", 0), ("false", 1)):
            with self.subTest(can_publish=can_publish):
                result, output = self.run_step(
                    "Select image for the tool definition",
                    docker_exit=1,
                    CAN_PUBLISH=can_publish,
                )
                self.assertEqual(result.returncode, expected_exit, result.stderr)
                self.assertEqual("build=true\n" in output, can_publish == "true")

    def test_missing_definition_hash_fails_before_selecting_an_image(self) -> None:
        result, output = self.run_step(
            "Select image for the tool definition", DEFINITION_HASH=""
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(output, "")

    def test_consumers_receive_only_a_valid_immutable_reference(self) -> None:
        for digest, expected_exit in (("sha256:" + "b" * 64, 0), ("invalid", 1)):
            with self.subTest(digest=digest):
                result, output = self.run_step(
                    "Resolve immutable image reference",
                    IMAGE="ghcr.io/rurusasu/dotfiles/bootstrap-ci-tools:tag",
                    DOCKER_RESULT=digest,
                )
                self.assertEqual(result.returncode, expected_exit, result.stderr)
                expected_output = (
                    f"image=ghcr.io/rurusasu/dotfiles/bootstrap-ci-tools@{digest}\n"
                    if expected_exit == 0
                    else ""
                )
                self.assertEqual(output, expected_output)


if __name__ == "__main__":
    unittest.main()
