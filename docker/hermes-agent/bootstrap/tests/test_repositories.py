"""Local-bare-remote coverage for shared Hermes repository synchronization."""

from __future__ import annotations

import fcntl
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from hermes_bootstrap.errors import MigrationError, RepositoryError
from hermes_bootstrap.github import GitAuth
from hermes_bootstrap.models import BootstrapManifest, SharedRepository
from hermes_bootstrap.payload import SecretRedactor
from hermes_bootstrap.repositories import (
    RemoteSyncResult,
    apply_shared_working_tree,
    synchronize_named_repository,
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


class RecordingTransaction:
    def __init__(self) -> None:
        self.snapshots: list[Path] = []
        self.moves: list[tuple[Path, Path]] = []

    def snapshot(self, path: Path) -> None:
        self.snapshots.append(path)

    def record_move(self, source: Path, target: Path) -> None:
        self.moves.append((source, target))


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
        self.auth = GitAuth("fixture-token", SecretRedactor(("fixture-token",)))

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def repository(self, *, mode: str = "read-write", legacy: bool = True) -> SharedRepository:
        return SharedRepository(
            name="lifelog",
            source=str(self.remote),
            ref="main",
            target=self.data_root / "shared" / "lifelog",
            mode=mode,  # type: ignore[arg-type]
            sync_owner="default" if mode == "read-write" else None,
            legacy_target=self.data_root / "core" / "lifelog" if legacy else None,
        )

    def clone(self, target: Path) -> None:
        target.parent.mkdir(parents=True, exist_ok=True)
        run_git("clone", "--branch", "main", str(self.remote), str(target))
        run_git("config", "user.name", "Fixture", cwd=target)
        run_git("config", "user.email", "fixture@example.test", cwd=target)

    def advance_remote(self, contents: str = "remote\n") -> str:
        (self.seed / "README.md").write_text(contents, encoding="utf-8")
        run_git("add", "README.md", cwd=self.seed)
        run_git("commit", "-m", "remote", cwd=self.seed)
        run_git("push", "origin", "main", cwd=self.seed)
        return run_git("rev-parse", "HEAD", cwd=self.seed)

    def test_initial_clone_is_staged_then_moved_and_linked(self) -> None:
        repo = self.repository()

        result = synchronize_remote(repo, self.auth)

        self.assertIsNotNone(result.working_tree)
        self.assertNotEqual(result.working_tree, repo.target)
        self.assertTrue((result.working_tree / ".git").is_dir())
        transaction = RecordingTransaction()
        changes = apply_shared_working_tree(repo, result, transaction)
        self.assertEqual(run_git("rev-parse", "HEAD", cwd=repo.target), result.commit)
        self.assertEqual(transaction.moves, [(result.working_tree, repo.target)])
        self.assertIn(repo.target, transaction.snapshots)
        self.assertEqual(os.readlink(repo.legacy_target), "../shared/lifelog")
        self.assertEqual(changes.changed_paths, tuple(sorted(changes.changed_paths, key=lambda path: path.as_posix())))

    def test_read_only_fast_forwards_and_rejects_dirty_or_diverged_checkouts(self) -> None:
        repo = self.repository(mode="read-only")
        self.clone(repo.target)
        expected = self.advance_remote()

        result = synchronize_remote(repo, self.auth)

        self.assertEqual(result.commit, expected)
        self.assertEqual(run_git("rev-parse", "HEAD", cwd=repo.target), expected)
        (repo.target / "local.txt").write_text("dirty\n", encoding="utf-8")
        with self.assertRaises(RepositoryError):
            synchronize_remote(repo, self.auth)
        (repo.target / "local.txt").unlink()
        (repo.target / "local.md").write_text("local\n", encoding="utf-8")
        run_git("add", "local.md", cwd=repo.target)
        run_git("commit", "-m", "local", cwd=repo.target)
        with self.assertRaises(RepositoryError):
            synchronize_remote(repo, self.auth)

    def test_read_write_commits_allowed_changes_and_retries_a_prior_unpushed_commit(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        (repo.target / "entry.md").write_text("entry\n", encoding="utf-8")

        result = synchronize_remote(repo, self.auth)

        self.assertTrue(result.pushed)
        self.assertEqual(run_git("rev-parse", "HEAD", cwd=repo.target), run_git("rev-parse", "origin/main", cwd=repo.target))
        (repo.target / "retry.md").write_text("retry\n", encoding="utf-8")
        hooks = self.remote / "hooks"
        reject = hooks / "pre-receive"
        reject.write_text("#!/bin/sh\nexit 1\n", encoding="utf-8")
        reject.chmod(0o700)
        with self.assertRaises(RepositoryError):
            synchronize_remote(repo, self.auth)
        reject.unlink()
        retried = synchronize_remote(repo, self.auth)
        self.assertTrue(retried.pushed)
        run_git("fetch", "origin", "main", cwd=self.seed)
        self.assertEqual(retried.commit, run_git("rev-parse", "FETCH_HEAD", cwd=self.seed))

    def test_read_write_rebases_onto_the_declared_remote_commit_before_pushing(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        (repo.target / "local.md").write_text("local\n", encoding="utf-8")
        self.advance_remote("remote\n")

        result = synchronize_remote(repo, self.auth)

        self.assertTrue(result.pushed)
        self.assertEqual((repo.target / "README.md").read_text(encoding="utf-8"), "remote\n")
        self.assertEqual((repo.target / "local.md").read_text(encoding="utf-8"), "local\n")

    def test_read_write_rejects_forbidden_status_paths_including_rename_pairs(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        (repo.target / ".env").write_text("secret\n", encoding="utf-8")
        with self.assertRaises(RepositoryError):
            synchronize_remote(repo, self.auth)
        (repo.target / ".env").unlink()
        (repo.target / "normal.txt").write_text("normal\n", encoding="utf-8")
        run_git("add", "normal.txt", cwd=repo.target)
        run_git("commit", "-m", "normal", cwd=repo.target)
        run_git("mv", "normal.txt", "token.txt", cwd=repo.target)
        with self.assertRaises(RepositoryError):
            synchronize_remote(repo, self.auth)

    def test_rejects_wrong_origin_and_lock_contention_without_secret_output(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        run_git("remote", "set-url", "origin", str(self.root / "wrong.git"), cwd=repo.target)
        with self.assertRaises(RepositoryError):
            synchronize_remote(repo, self.auth)
        run_git("remote", "set-url", "origin", str(self.remote), cwd=repo.target)
        lock = self.data_root / "locks" / "repositories" / "lifelog.lock"
        lock.parent.mkdir(parents=True, exist_ok=True)
        with lock.open("w", encoding="utf-8") as handle:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaisesRegex(RepositoryError, "lifelog\\.lock") as caught:
                synchronize_remote(repo, self.auth)
        self.assertNotIn("fixture-token", str(caught.exception))
        self.assertEqual(list(repo.target.parent.glob("askpass-*")), [])

    def test_apply_migrates_legacy_rejects_two_real_paths_and_is_idempotent(self) -> None:
        repo = self.repository()
        self.clone(repo.legacy_target)
        result = synchronize_remote(repo, self.auth)
        transaction = RecordingTransaction()
        apply_shared_working_tree(repo, result, transaction)
        self.assertTrue(repo.target.is_dir())
        self.assertTrue(repo.legacy_target.is_symlink())
        self.assertEqual(apply_shared_working_tree(repo, result, RecordingTransaction()).changed_paths, ())

        repo.legacy_target.unlink()
        self.clone(repo.legacy_target)
        with self.assertRaises(MigrationError):
            apply_shared_working_tree(repo, result, RecordingTransaction())

    def test_apply_ignores_empty_paths_and_runtime_requires_canonical_checkout(self) -> None:
        repo = self.repository()
        repo.target.mkdir(parents=True)
        repo.legacy_target.parent.mkdir(parents=True)
        repo.legacy_target.mkdir()
        result = synchronize_remote(repo, self.auth)
        apply_shared_working_tree(repo, result, RecordingTransaction())
        manifest = BootstrapManifest(1, self.data_root, (), None, (), (repo,))  # type: ignore[arg-type]
        synced = synchronize_named_repository("lifelog", manifest, self.auth, require_canonical=True)
        self.assertEqual(synced.working_tree, repo.target)
        shutil.rmtree(repo.target)
        with self.assertRaises(RepositoryError):
            synchronize_named_repository("lifelog", manifest, self.auth, require_canonical=True)

    def test_unknown_named_repository_is_rejected(self) -> None:
        repo = self.repository()
        manifest = BootstrapManifest(1, self.data_root, (), None, (), (repo,))  # type: ignore[arg-type]
        with self.assertRaises(RepositoryError):
            synchronize_named_repository("unknown", manifest, self.auth)

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
