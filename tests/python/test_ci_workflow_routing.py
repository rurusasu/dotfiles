"""Exercise platform build and cache export steps from the CI workflow."""

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
WORKFLOWS_DIRECTORY = REPOSITORY_ROOT / ".github" / "workflows"


class CiWorkflowRoutingContractTests(unittest.TestCase):
    """Run build steps with external commands replaced at the process boundary."""

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
            nix = directory / "nix"
            nix.write_text(
                f"#!{sys.executable}\n"
                "import json, os, sys\n"
                "with open(os.environ['INVOCATION_LOG'], 'w') as log:\n"
                "    log.write(json.dumps({'argv': sys.argv[1:], 'identity': "
                "{key: os.environ.get(key) for key in "
                "('DOTFILES_USER', 'DOTFILES_HOME')}}))\n"
                "print('/nix/store/' + 'b' * 32 + '-system')\n"
            )
            nix.chmod(0o755)
            environment = dict(os.environ)
            environment.update(
                PATH=f"{directory}:{environment['PATH']}",
                GITHUB_WORKSPACE=temporary,
                INVOCATION_LOG=str(directory / "invocation.json"),
            )
            for variable in (
                "DOTFILES_USER",
                "DOTFILES_HOME",
            ):
                environment.pop(variable, None)
            subprocess.run(
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
            invocation = json.loads((directory / "invocation.json").read_text())
        self.assertEqual(invocation["argv"][:2], ["build", "--impure"])
        self.assertIn(
            ".#nixosConfigurations.linux.config.system.build.toplevel",
            invocation["argv"],
        )
        self.assertIn(
            ".#homeConfigurations.x86_64-linux.activationPackage", invocation["argv"]
        )
        self.assertEqual(
            invocation["identity"],
            {
                "DOTFILES_USER": None,
                "DOTFILES_HOME": None,
            },
        )

    def test_wsl_prebuild_exports_zstd_cache_and_fails_closed(self) -> None:
        workflow = self._named_workflow("ci-nix.yml")
        job = self._workflow_job(workflow, "wsl-prebuild")
        script = re.search(
            r"(?m)^      - name: Build the WSL system closure and export a local cache\n"
            r"        id: wsl-cache\n        shell: bash\n"
            r"        run: \|\n(?P<script>(?:          [^\n]*\n|\n)+)",
            job,
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
                    "    cache = pathlib.Path(target.path)\n"
                    "    (cache / 'nar').mkdir(exist_ok=True)\n"
                    "    (cache / 'nar/private.nar.zst').write_text('cache')\n"
                    "    (cache / (paths[0].split('/')[-1].split('-')[0] + '.narinfo')).write_text(\n"
                    "        f'StorePath: {paths[0]}\\nURL: nar/private.nar.zst\\nReferences: \\n')\n"
                    "elif sys.argv[1:3] == ['path-info', '--recursive']:\n"
                    "    print(paths[0])\n"
                    "else:\n"
                    "    raise SystemExit(64)\n"
                )
                nix.chmod(0o755)
                nix_store = directory / "nix-store"
                nix_store.write_text(
                    f"#!{sys.executable}\n"
                    "import sys\n"
                    "assert sys.argv[1:5] == ['--store', 'https://cache.nixos.org', '--check-validity', '--print-invalid']\n"
                    "print('\\n'.join(sys.argv[5:]))\n"
                )
                nix_store.chmod(0o755)
                environment = dict(os.environ)
                environment.update(
                    PATH=f"{directory}:{environment['PATH']}",
                    RUNNER_TEMP=str(runner_temp),
                    GITHUB_OUTPUT=str(output),
                    COPY_EXIT=str(copy_exit),
                    DOTFILES_CI_BINARY_CACHE=str(runner_temp / "persistent-cache"),
                )
                (runner_temp / "persistent-cache").mkdir()
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
                    self.assertIn("./nar/private.nar.zst", archive.getnames())
                    self.assertIn("./public-paths.txt", archive.getnames())
                self.assertTrue(
                    (runner_temp / "persistent-cache/nar/private.nar.zst").is_file(),
                    "transport pruning must preserve the persistent cache",
                )


if __name__ == "__main__":
    unittest.main()
