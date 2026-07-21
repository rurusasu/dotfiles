from __future__ import annotations

import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import FrameType, TracebackType
from unittest import mock


BOOTSTRAP_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BOOTSTRAP_ROOT))

from hermes_bootstrap.errors import RepositoryError
from hermes_bootstrap.git import StagedSource, assert_safe_distribution_tree, stage_distribution
import hermes_bootstrap.git as git_module
from hermes_bootstrap.github import GitAuth
from hermes_bootstrap.models import DistributionSource
from hermes_bootstrap.payload import SecretRedactor


def auth() -> GitAuth:
    token = "git-token-marker"
    return GitAuth(token=token, redactor=SecretRedactor((token,)))


def git(*arguments: str, cwd: Path | None = None) -> str:
    return subprocess.run(
        ("git", *arguments), cwd=cwd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    ).stdout.strip()


class GitStagingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.remote = self.root / "source.git"
        self.checkout = self.root / "checkout"
        self.workdir = self.root / "work"
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

    def source(self, *, ref: str = "main", manifest: str = "distribution.yaml") -> DistributionSource:
        return DistributionSource("rick", str(self.remote), ref, Path("/opt/data/profiles/rick"), manifest)

    def assert_hidden(self, error: BaseException, *markers: str) -> None:
        pending: list[object] = [error]
        visited: set[int] = set()
        while pending:
            value = pending.pop()
            if id(value) in visited:
                continue
            visited.add(id(value))
            if isinstance(value, str):
                for marker in markers:
                    self.assertNotIn(marker, value)
            elif isinstance(value, bytes):
                for marker in markers:
                    self.assertNotIn(marker.encode(), value)
            elif isinstance(value, BaseException):
                pending.extend((value.__cause__, value.__context__, value.__traceback__, value.args))
            elif isinstance(value, TracebackType):
                pending.extend((value.tb_frame, value.tb_next))
            elif isinstance(value, FrameType):
                pending.extend(value.f_locals.values())
            elif isinstance(value, dict):
                pending.extend((*value.keys(), *value.values()))
            elif isinstance(value, (list, tuple, set, frozenset)):
                pending.extend(value)

    def test_stages_a_detached_exact_sha_without_git_metadata(self) -> None:
        expected = git("rev-parse", "HEAD", cwd=self.checkout)
        staged = stage_distribution(self.source(), self.workdir, auth())

        self.assertIsInstance(staged, StagedSource)
        self.assertEqual(staged.commit, expected)
        self.assertEqual((staged.path / "config.yaml").read_text(encoding="utf-8"), "value: one\n")
        self.assertFalse((staged.path / ".git").exists())
        self.assertEqual(stat.S_IMODE(staged.path.stat().st_mode), 0o700)

    def test_askpass_is_private_token_free_and_removed_after_staging(self) -> None:
        observed: list[tuple[Path, dict[str, str]]] = []
        real_run = subprocess.run

        def inspect(command: object, **kwargs: object) -> object:
            environment = kwargs["env"]
            askpass = Path(environment["GIT_ASKPASS"])
            observed.append((askpass, environment))
            self.assertEqual(stat.S_IMODE(askpass.stat().st_mode), 0o700)
            self.assertNotIn("git-token-marker", askpass.read_text(encoding="utf-8"))
            return real_run(command, **kwargs)

        with mock.patch("hermes_bootstrap.git.subprocess.run", side_effect=inspect):
            stage_distribution(self.source(), self.workdir, auth())

        self.assertTrue(observed)
        for askpass, environment in observed:
            self.assertFalse(askpass.exists())
            self.assertEqual(environment["GIT_TERMINAL_PROMPT"], "0")
            self.assertEqual(environment["HERMES_BOOTSTRAP_GITHUB_TOKEN"], "git-token-marker")

    def test_missing_ref_and_non_commit_clean_partial_stage(self) -> None:
        for source in (
            self.source(ref="missing"),
            self.source(ref="HEAD^{tree}"),
        ):
            with self.subTest(source=source.source, ref=source.ref):
                with self.assertRaises(RepositoryError):
                    stage_distribution(source, self.workdir, auth())
                self.assertEqual(list(self.workdir.glob("stage-*")), [])
                self.assertEqual(list(self.workdir.glob("askpass-*")), [])

    def test_observed_remote_identity_mismatch_is_rejected_after_successful_clone(self) -> None:
        real_run = git_module._run_git

        def tampered(arguments: tuple[str, ...], cwd: Path, environment: dict[str, str]) -> str | None:
            output = real_run(arguments, cwd, environment)
            if arguments == ("config", "--get", "remote.origin.url"):
                return str(self.remote) + "-tampered"
            return output

        with mock.patch("hermes_bootstrap.git._run_git", side_effect=tampered):
            with self.assertRaises(RepositoryError):
                stage_distribution(self.source(), self.workdir, auth())
        self.assertEqual(list(self.workdir.glob("stage-*")), [])

    def test_invalid_auth_and_credential_bearing_source_fail_before_clone(self) -> None:
        invalid = GitAuth(token="", redactor=SecretRedactor(()))
        with self.assertRaises(RepositoryError):
            stage_distribution(self.source(), self.workdir, invalid)
        credential_url = DistributionSource(
            "rick",
            "https://user:git-token-marker@example.test/repository.git",
            "main",
            Path("/opt/data/profiles/rick"),
            "distribution.yaml",
        )
        with self.assertRaises(RepositoryError) as caught:
            stage_distribution(credential_url, self.workdir, auth())
        self.assert_hidden(caught.exception, "git-token-marker")
        self.assertEqual(list(self.workdir.glob("stage-*")), [])

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

    def test_rejects_symlink_special_file_and_missing_manifest(self) -> None:
        stage = self.root / "unsafe"
        stage.mkdir()
        (stage / "distribution.yaml").write_text("name: rick\n", encoding="utf-8")
        (stage / "link").symlink_to("distribution.yaml")
        unsafe = StagedSource(self.source(), stage, "a" * 40)
        with self.assertRaises(RepositoryError):
            assert_safe_distribution_tree(unsafe)

        (stage / "link").unlink()
        os.mkfifo(stage / "fifo")
        self.addCleanup(lambda: (stage / "fifo").exists() and (stage / "fifo").unlink())
        with self.assertRaises(RepositoryError):
            assert_safe_distribution_tree(unsafe)

        with self.assertRaises(RepositoryError):
            stage_distribution(self.source(manifest="missing.yaml"), self.workdir, auth())
