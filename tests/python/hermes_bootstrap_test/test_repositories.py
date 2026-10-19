"""Local-bare-remote coverage for shared Hermes repository synchronization."""

from __future__ import annotations

import stat
import subprocess
import tempfile
import unittest
import traceback
from pathlib import Path
from unittest import mock

import hermes_bootstrap.repositories as repositories_module
from hermes_bootstrap.errors import RepositoryError
from hermes_bootstrap.github import GitAuth
from hermes_bootstrap.models import SharedRepository
from hermes_bootstrap.repositories import (
    apply_shared_working_tree,
    synchronize_remote,
)


def run_git(*arguments: str, cwd: Path | None = None) -> str:
    result = subprocess.run(
        ("git", *arguments),
        cwd=cwd,
        check=True,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return result.stdout.strip()


def run_git_bytes(*arguments: str, cwd: Path | None = None) -> bytes:
    return subprocess.run(
        ("git", *arguments),
        cwd=cwd,
        check=True,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    ).stdout


class RepositoryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.data_root = self.root / "data"
        self.remote = self.root / "remote.git"
        self.seed = self.root / "seed"
        run_git("init", "--bare", str(self.remote))
        run_git("init", "--initial-branch=main", str(self.seed))
        run_git("config", "user.name", "Fixture", cwd=self.seed)
        run_git("config", "user.email", "fixture@example.test", cwd=self.seed)
        (self.seed / "README.md").write_text("initial\n", encoding="utf-8")
        run_git("add", "README.md", cwd=self.seed)
        run_git("commit", "-m", "initial", cwd=self.seed)
        run_git("remote", "add", "origin", str(self.remote), cwd=self.seed)
        run_git("push", "-u", "origin", "main", cwd=self.seed)
        self.auth = GitAuth("fixture-token")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def repository(self) -> SharedRepository:
        return SharedRepository(
            name="lifelog",
            source=str(self.remote),
            ref="main",
            target=self.data_root / "shared" / "lifelog",
        )

    def clone(self, target: Path) -> None:
        target.parent.mkdir(parents=True, exist_ok=True)
        run_git("clone", "--no-hardlinks", "--branch", "main", str(self.remote), str(target))
        run_git("config", "user.name", "Fixture", cwd=target)
        run_git("config", "user.email", "fixture@example.test", cwd=target)

    def advance_remote(self, contents: str = "remote\n") -> str:
        (self.seed / "README.md").write_text(contents, encoding="utf-8")
        run_git("add", "README.md", cwd=self.seed)
        run_git("commit", "-m", "remote", cwd=self.seed)
        run_git("push", "origin", "main", cwd=self.seed)
        return run_git("rev-parse", "HEAD", cwd=self.seed)

    def remote_head(self) -> str:
        return run_git("--git-dir", str(self.remote), "rev-parse", "main")

    def create_nested_repository(self, path: Path) -> None:
        run_git("init", "--initial-branch=main", str(path))
        run_git("config", "user.name", "Nested", cwd=path)
        run_git("config", "user.email", "nested@example.test", cwd=path)
        (path / "nested.txt").write_text("nested\n", encoding="utf-8")
        run_git("add", "nested.txt", cwd=path)
        run_git("commit", "-m", "nested", cwd=path)

    def assert_secret_free_error(self, error: BaseException, *markers: str) -> None:
        rendered = str(error) + repr(error) + "".join(traceback.format_exception(error))
        for marker in markers:
            self.assertNotIn(marker, rendered)

    def test_failed_push_preserves_local_changes_for_rerun(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        (repo.target / "retry.md").write_text("retry\n", encoding="utf-8")
        hooks = self.remote / "hooks"
        reject = hooks / "pre-receive"
        reject.write_text("#!/bin/sh\nexit 1\n", encoding="utf-8")
        reject.chmod(0o700)
        with self.assertRaises(RepositoryError):
            synchronize_remote(repo, self.auth)
        self.assertEqual(
            run_git("rev-list", "--count", "FETCH_HEAD..HEAD", cwd=repo.target),
            "0",
        )
        self.assertEqual((repo.target / "retry.md").read_text(encoding="utf-8"), "retry\n")
        reject.unlink()
        retried = synchronize_remote(repo, self.auth)
        self.assertTrue(retried.pushed)
        run_git("fetch", "origin", "main", cwd=self.seed)
        self.assertEqual(retried.commit, run_git("rev-parse", "FETCH_HEAD", cwd=self.seed))

    def test_read_write_does_not_run_checkout_hooks_with_the_github_token(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        marker = self.root / "hook-token-marker"
        hook = repo.target / ".git" / "hooks" / "pre-commit"
        hook.write_text(
            f"#!/bin/sh\nprintf '%s' \"$HERMES_BOOTSTRAP_GITHUB_TOKEN\" > '{marker}'\n",
            encoding="utf-8",
        )
        hook.chmod(0o700)
        (repo.target / "entry.md").write_text("entry\n", encoding="utf-8")

        result = synchronize_remote(repo, self.auth)

        self.assertTrue(result.pushed)
        self.assertFalse(marker.exists())

    def test_preexisting_unpushed_commit_is_rejected_and_preserved(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        (repo.target / "README.md").write_text("local conflict\n", encoding="utf-8")
        run_git("add", "README.md", cwd=repo.target)
        run_git("commit", "-m", "local conflict", cwd=repo.target)
        local_commit = run_git("rev-parse", "HEAD", cwd=repo.target)
        self.advance_remote("remote conflict\n")

        with self.assertRaises(RepositoryError):
            synchronize_remote(repo, self.auth)

        self.assertEqual(run_git("rev-parse", "HEAD", cwd=repo.target), local_commit)
        self.assertEqual(run_git_bytes("status", "--porcelain=v1", "-z", cwd=repo.target), b"")
        self.assertEqual((repo.target / "README.md").read_text(encoding="utf-8"), "local conflict\n")

    def test_non_fast_forward_push_race_is_rejected_without_force(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        (repo.target / "local-race.md").write_text("local\n", encoding="utf-8")
        (self.seed / "remote-race.md").write_text("remote\n", encoding="utf-8")
        run_git("add", "remote-race.md", cwd=self.seed)
        run_git("commit", "-m", "race", cwd=self.seed)
        race_commit = run_git("rev-parse", "HEAD", cwd=self.seed)
        run_git("push", "origin", "HEAD:refs/heads/race", cwd=self.seed)
        real_runner = repositories_module._run_git_bytes
        raced = False

        def race_before_push(
            arguments: tuple[str, ...],
            cwd: Path,
            environment: dict[str, str],
            *,
            max_output_bytes: int,
        ) -> bytes | None:
            nonlocal raced
            if arguments and arguments[0] == "push" and not raced:
                raced = True
                run_git("--git-dir", str(self.remote), "update-ref", "refs/heads/main", race_commit)
            return real_runner(arguments, cwd, environment, max_output_bytes=max_output_bytes)

        with mock.patch.object(repositories_module, "_run_git_bytes", side_effect=race_before_push):
            with self.assertRaises(RepositoryError):
                synchronize_remote(repo, self.auth)

        self.assertTrue(raced)
        self.assertEqual(self.remote_head(), race_commit)
        self.assertNotEqual(run_git("rev-parse", "HEAD", cwd=repo.target), race_commit)

    def test_untracked_nested_repository_failure_preserves_the_original_index(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        self.create_nested_repository(repo.target / "nested")
        before_status = run_git_bytes("status", "--porcelain=v1", "-z", "--untracked-files=all", cwd=repo.target)
        before_index = (repo.target / ".git" / "index").read_bytes()

        with self.assertRaises(RepositoryError):
            synchronize_remote(repo, self.auth)

        self.assertEqual((repo.target / ".git" / "index").read_bytes(), before_index)
        self.assertEqual(
            run_git_bytes("status", "--porcelain=v1", "-z", "--untracked-files=all", cwd=repo.target),
            before_status,
        )

    def test_rejects_wrong_origin_without_secret_output(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        run_git("remote", "set-url", "origin", str(self.root / "wrong.git"), cwd=repo.target)
        with self.assertRaises(RepositoryError) as caught:
            synchronize_remote(repo, self.auth)
        self.assert_secret_free_error(caught.exception, "fixture-token")
        self.assertEqual(list(repo.target.parent.glob("askpass-*")), [])

    def test_apply_preserves_an_existing_unmanaged_canonical_target(self) -> None:
        repo = self.repository()
        result = synchronize_remote(repo, self.auth)
        repo.target.mkdir()
        repo.target.chmod(0o750)

        existing = repo.target / "existing.md"
        existing.write_text("preserve existing data\n", encoding="utf-8")

        with self.assertRaises(RepositoryError):
            apply_shared_working_tree(repo, result)

        self.assertEqual(existing.read_text(encoding="utf-8"), "preserve existing data\n")
        self.assertEqual(stat.S_IMODE(repo.target.stat().st_mode), 0o750)
        self.assertTrue((result.working_tree / ".git").is_dir())

    def test_read_write_sync_preserves_a_real_non_ascii_filename(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        filename = "日本語-記録.md"
        (repo.target / filename).write_text("unicode\n", encoding="utf-8")

        result = synchronize_remote(repo, self.auth)

        self.assertTrue(result.pushed)
        self.assertEqual((repo.target / filename).read_text(encoding="utf-8"), "unicode\n")


if __name__ == "__main__":
    unittest.main()
