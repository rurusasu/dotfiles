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
from unittest import mock

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS_DIRECTORY = REPOSITORY_ROOT / ".github" / "workflows"


class CiWorkflowRoutingContractTests(unittest.TestCase):
    """Run build steps with external commands replaced at the process boundary."""

    def test_cache_pruning_deletes_only_older_confirmed_main_generations(self) -> None:
        with mock.patch.object(sys, "path", [str(REPOSITORY_ROOT / "scripts/python"), *sys.path]):
            from prepare_ci_nix_cache import prune_cache

        prefix = "ci-nix-v2-test-"
        key = prefix + "current"
        old = {"id": 1, "key": prefix + "old", "ref": "refs/heads/main", "created_at": "2026-01"}
        protected = [
            old | {"id": 2, "key": "unrelated-old"},
            old | {"id": 3, "ref": "refs/pull/1/merge"},
            old | {"id": 4, "created_at": "2026-03"},
        ]
        environment = {
            "GITHUB_REF": "refs/heads/main", "GITHUB_API_URL": "https://api.github.com",
            "GITHUB_REPOSITORY": "owner/repo", "GITHUB_TOKEN": "fixture-token",
        }
        for confirmed in (False, True):
            pages = [{"actions_caches": [old, *protected]}, {"actions_caches": []}]
            if confirmed:
                pages[1]["actions_caches"].append(old | {"id": 5, "key": key, "created_at": "2026-02"})
            with (
                self.subTest(confirmed=confirmed),
                mock.patch.dict(os.environ, environment),
                mock.patch("prepare_ci_nix_cache.subprocess.run", return_value=subprocess.CompletedProcess([], 0, json.dumps(pages))) as run,
            ):
                prune_cache(key, prefix)
                self.assertIn("--paginate", run.call_args_list[0].args[0])
                self.assertIn("--slurp", run.call_args_list[0].args[0])
                deleted = [call.args[0][-1] for call in run.call_args_list if "DELETE" in call.args[0]]
                self.assertEqual(deleted, ["https://api.github.com/repos/owner/repo/actions/caches/1"] if confirmed else [])
                self.assertNotIn("fixture-token", str([call.args for call in run.call_args_list]))
        with (
            mock.patch.dict(os.environ, environment),
            mock.patch("prepare_ci_nix_cache.subprocess.run", side_effect=subprocess.CalledProcessError(1, ["gh", "api"])) as run,
        ):
            prune_cache(key, prefix)
            self.assertEqual(run.call_count, 1)

    def _workflow_job(self, name: str) -> str:
        job = re.search(
            rf"(?ms)^  {re.escape(name)}:\n(?P<job>.*?)(?=^  [a-zA-Z0-9_-]+:\s*$|\Z)",
            (WORKFLOWS_DIRECTORY / "ci-nix.yml").read_text(encoding="utf-8"),
        )
        self.assertIsNotNone(job, f"missing {name} job")
        return job.group("job") if job is not None else ""

    def test_linux_build_installs_declared_hardware_without_identity_inference(
        self,
    ) -> None:
        job = self._workflow_job("linux-build")
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
                "#!/bin/bash\n"
                "[[ ! -v DOTFILES_USER && ! -v DOTFILES_HOME ]] || exit 64\n"
                'printf "%s\\0" "$@" > "$INVOCATION_LOG"\n'
                f"printf '/nix/store/{'b' * 32}-system\\n'\n"
            )
            nix.chmod(0o755)
            installer = directory / "install"
            installer.write_text(
                '#!/bin/bash\nprintf "%s\\0" "$@" > "$INSTALL_LOG"\n'
            )
            installer.chmod(0o755)
            environment = dict(os.environ)
            environment.update(
                PATH=f"{directory}:{environment['PATH']}",
                GITHUB_WORKSPACE=temporary,
                INVOCATION_LOG=str(directory / "invocation"),
                INSTALL_LOG=str(directory / "install-arguments"),
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
            invocation = (directory / "invocation").read_text().split("\0")[:-1]
            self.assertEqual(
                (directory / "install-arguments").read_text().split("\0")[:-1],
                [
                    "-D",
                    "-m",
                    "0644",
                    f"{temporary}/nix/tests/fixtures/hardware-configuration.nix",
                    "/etc/nixos/hardware-configuration.nix",
                ],
            )
        self.assertEqual(invocation[:2], ["build", "--impure"])
        self.assertIn(
            ".#nixosConfigurations.linux.config.system.build.toplevel",
            invocation,
        )
        self.assertIn(
            ".#homeConfigurations.x86_64-linux.activationPackage", invocation
        )

    def test_wsl_prebuild_exports_zstd_cache_and_fails_closed(self) -> None:
        job = self._workflow_job("wsl-prebuild")
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
        for copy_exit, nar_url, references, expected_exit, diagnostic in (
            (0, "nar/private.nar.zst", "", 0, ""),
            (47, "nar/private.nar.zst", "", 47, ""),
            (0, "../outside.nar", "", 1, "Invalid NAR location"),
            (0, "nar/missing.nar", "", 1, "Missing NAR payload"),
            (0, "nar/private.nar.zst", "outside-closure", 1, "Incomplete reference closure"),
        ):
            with (
                self.subTest(copy_exit=copy_exit, nar_url=nar_url, references=references),
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
                    "        f'StorePath: {paths[0]}\\nURL: {os.environ[\"NAR_URL\"]}\\nReferences: {os.environ[\"NAR_REFS\"]}\\n')\n"
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
                    NAR_URL=nar_url,
                    NAR_REFS=references,
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
                    result.returncode, expected_exit, result.stdout + result.stderr
                )
                if expected_exit:
                    if diagnostic:
                        self.assertIn(diagnostic, result.stderr)
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
                    if not copy_exit:
                        self.assertTrue((runner_temp / "persistent-cache/nar/private.nar.zst").is_file())
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
