from __future__ import annotations

import os
import errno
import stat
import subprocess
import sys
import tempfile
import time
import traceback
import unittest
from pathlib import Path
from unittest import mock


BOOTSTRAP_ROOT = Path(__file__).resolve().parents[3] / "scripts" / "python"
sys.path.insert(0, str(BOOTSTRAP_ROOT))

from hermes_bootstrap.errors import RepositoryError
from hermes_bootstrap.git import stage_distribution
import hermes_bootstrap.git as git_module
from hermes_bootstrap.github import GitAuth
from hermes_bootstrap.models import DistributionSource


def auth() -> GitAuth:
    token = "git-token-marker"
    return GitAuth(token=token)


def git(*arguments: str, cwd: Path | None = None) -> str:
    return subprocess.run(
        ("git", *arguments), cwd=cwd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    ).stdout.strip()


class GitStagingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.remote = self.root / "source.git"
        self.checkout = self.root / "checkout"
        self.workdir = self.root / "work"

    def seed_source(self) -> None:
        git("init", "--bare", str(self.remote))
        git("clone", str(self.remote), str(self.checkout))
        git("config", "user.name", "Bootstrap Test", cwd=self.checkout)
        git("config", "user.email", "bootstrap@example.test", cwd=self.checkout)
        (self.checkout / "distribution.yaml").write_text("name: rick\n", encoding="utf-8")
        (self.checkout / "config.yaml").write_text("value: one\n", encoding="utf-8")
        git("add", ".", cwd=self.checkout)
        git("commit", "-m", "initial", cwd=self.checkout)
        git("branch", "-M", "main", cwd=self.checkout)
        git("push", "-u", "origin", "main", cwd=self.checkout)

    def source(self) -> DistributionSource:
        return DistributionSource(
            "rick",
            str(self.remote),
            "main",
            Path("/opt/data/profiles/rick"),
            "distribution.yaml",
        )

    def assert_hidden(self, error: BaseException, *markers: str) -> None:
        rendered = str(error) + repr(error) + "".join(traceback.format_exception(error))
        for marker in markers:
            self.assertNotIn(marker, rendered)

    def test_askpass_is_private_token_free_and_removed_after_staging(self) -> None:
        self.seed_source()
        observed: list[tuple[Path, dict[str, str]]] = []
        real_popen = subprocess.Popen

        def inspect(command: object, **kwargs: object) -> object:
            environment = kwargs["env"]
            askpass = Path(environment["GIT_ASKPASS"])
            observed.append((askpass, environment))
            self.assertEqual(stat.S_IMODE(askpass.stat().st_mode), 0o700)
            self.assertNotIn("git-token-marker", askpass.read_text(encoding="utf-8"))
            self.assertNotIn("git-token-marker", repr(command))
            return real_popen(command, **kwargs)

        with mock.patch("hermes_bootstrap.git.subprocess.Popen", side_effect=inspect):
            stage_distribution(self.source(), self.workdir, auth())

        self.assertTrue(observed)
        for askpass, environment in observed:
            self.assertFalse(askpass.exists())
            self.assertEqual(environment["GIT_TERMINAL_PROMPT"], "0")
            self.assertEqual(environment["HERMES_BOOTSTRAP_GITHUB_TOKEN"], "git-token-marker")

    def test_oversized_git_output_is_killed_and_partial_stage_is_removed(self) -> None:
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        pid_file = self.root / "git.pid"
        fake_git = bin_dir / "git"
        fake_git.write_text(
            "#!/bin/sh\n"
            "printf '%s\\n' \"$$\" > \"$HERMES_TEST_GIT_PID\"\n"
            "while :; do printf 'infinite-git-output-marker'; done\n",
            encoding="utf-8",
        )
        fake_git.chmod(0o700)

        with (
            mock.patch.object(git_module, "_GIT_EXECUTABLE", str(fake_git)),
            mock.patch.object(git_module, "_trusted_git_executable", return_value=str(fake_git)),
            mock.patch.dict(
                os.environ,
                {
                    "PATH": str(bin_dir),
                    "HERMES_TEST_GIT_PID": str(pid_file),
                },
                clear=False,
            ),
        ):
            with self.assertRaises(RepositoryError) as caught:
                stage_distribution(self.source(), self.workdir, auth())

        self.assert_hidden(caught.exception, "infinite-git-output-marker", "git-token-marker")
        self.assertEqual(list(self.workdir.glob("stage-*")), [])
        self.assertTrue(pid_file.exists())
        pid = int(pid_file.read_text(encoding="utf-8").strip())
        for _ in range(50):
            try:
                os.kill(pid, 0)
            except OSError as error:
                if error.errno == errno.ESRCH:
                    break
                raise
            time.sleep(0.01)
        else:
            self.fail("infinite Git output process was not reaped")

    def test_git_runner_ignores_checkout_controlled_path_entries(self) -> None:
        git("init", str(self.checkout))
        binary_directory = self.checkout / "bin"
        binary_directory.mkdir()
        marker = self.root / "path-marker"
        fake_git = binary_directory / "git"
        fake_git.write_text(
            "#!/bin/sh\nprintf 'executed' > \"$HERMES_TEST_MARKER\"\n",
            encoding="utf-8",
        )
        fake_git.chmod(0o700)

        environment = {"PATH": str(binary_directory), "HERMES_TEST_MARKER": str(marker)}
        self.assertEqual(git_module._run_git(("status", "--porcelain"), self.checkout, environment), "?? bin/")
        self.assertFalse(marker.exists())

    def test_timeout_kills_and_waits_for_the_git_child(self) -> None:
        fake_git = self.root / "slow-git"
        fake_git.write_text("#!/bin/sh\nexec /bin/sleep 10\n", encoding="utf-8")
        fake_git.chmod(0o700)
        processes: list[subprocess.Popen[bytes]] = []
        real_popen = subprocess.Popen

        def record_process(*arguments: object, **options: object) -> subprocess.Popen[bytes]:
            process = real_popen(*arguments, **options)
            processes.append(process)
            return process

        with (
            mock.patch.object(git_module, "_trusted_git_executable", return_value=str(fake_git)),
            mock.patch.object(git_module, "_GIT_TIMEOUT_SECONDS", 0.1),
            mock.patch.object(git_module.subprocess, "Popen", side_effect=record_process),
        ):
            self.assertIsNone(git_module._run_git_bytes(("status",), self.root, os.environ.copy()))

        self.assertEqual(len(processes), 1)
        self.assertIsNotNone(processes[0].returncode)

    def test_git_environment_strips_inherited_control_and_askpass_settings(self) -> None:
        askpass = self.root / "askpass"
        inherited = {
            "GIT_CONFIG_GLOBAL": "/tmp/credential-helper-marker",
            "GIT_ASKPASS": "/tmp/git-askpass-marker",
            "GIT_SSH_COMMAND": "ssh -F /tmp/git-ssh-marker",
            "SSH_ASKPASS": "/tmp/ssh-askpass-marker",
            "PATH": str(self.root),
        }
        with mock.patch.dict(os.environ, inherited, clear=False):
            environment = git_module._git_environment(auth(), askpass)

        self.assertEqual(environment["GIT_ASKPASS"], str(askpass))
        self.assertEqual(environment["GIT_TERMINAL_PROMPT"], "0")
        self.assertEqual(environment["GIT_CONFIG_NOSYSTEM"], "1")
        self.assertEqual(environment["GIT_CONFIG_GLOBAL"], os.devnull)
        self.assertEqual(environment["PATH"], os.defpath)
        self.assertEqual(environment["HERMES_BOOTSTRAP_GITHUB_TOKEN"], "git-token-marker")
        for key in ("GIT_SSH_COMMAND", "SSH_ASKPASS"):
            self.assertNotIn(key, environment)

    def test_git_failures_hide_token_and_stderr(self) -> None:
        missing = DistributionSource(
            "rick",
            str(self.root / "stderr-marker"),
            "main",
            Path("/opt/data/profiles/rick"),
            "distribution.yaml",
        )
        with self.assertRaises(RepositoryError) as caught:
            stage_distribution(missing, self.workdir, auth())
        self.assertIsNone(caught.exception.__cause__)
        self.assertIsNone(caught.exception.__context__)
        self.assert_hidden(caught.exception, "git-token-marker", "stderr-marker")
        self.assertEqual(list(self.workdir.glob("stage-*")), [])
