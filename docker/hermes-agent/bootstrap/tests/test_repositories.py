"""Local-bare-remote coverage for shared Hermes repository synchronization."""

from __future__ import annotations

import fcntl
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from dataclasses import replace
from pathlib import Path
from types import FrameType, TracebackType
from unittest import mock

import hermes_bootstrap.repositories as repositories_module
import hermes_bootstrap.transaction as transaction_module
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
from hermes_bootstrap.transaction import Transaction


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


class RecordingTransaction:
    def __init__(self) -> None:
        self.snapshots: list[Path] = []
        self.moves: list[tuple[Path, Path]] = []

    def snapshot(self, path: Path) -> None:
        self.snapshots.append(path)

    def record_move(self, source: Path, target: Path) -> None:
        self.moves.append((source, target))


class SwappingTransaction(RecordingTransaction):
    def __init__(self) -> None:
        super().__init__()
        self.held: Path | None = None

    def record_move(self, source: Path, target: Path) -> None:
        super().record_move(source, target)
        held = source.with_name(f"{source.name}-held")
        source.rename(held)
        source.symlink_to(held)
        self.held = held


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

    def remote_head(self, remote: Path | None = None, ref: str = "main") -> str:
        return run_git("--git-dir", str(self.remote if remote is None else remote), "rev-parse", ref)

    def create_nested_repository(self, path: Path) -> None:
        run_git("init", "--initial-branch=main", str(path))
        run_git("config", "user.name", "Nested", cwd=path)
        run_git("config", "user.email", "nested@example.test", cwd=path)
        (path / "nested.txt").write_text("nested\n", encoding="utf-8")
        run_git("add", "nested.txt", cwd=path)
        run_git("commit", "-m", "nested", cwd=path)

    def assert_hidden_in_bootstrap_error_graph(self, error: BaseException, *markers: str) -> None:
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
                if "hermes_bootstrap" in value.f_code.co_filename:
                    pending.extend(value.f_locals.values())
            elif isinstance(value, dict):
                pending.extend((*value.keys(), *value.values()))
            elif isinstance(value, (list, tuple, set, frozenset)):
                pending.extend(value)

    def test_initial_clone_is_staged_then_moved_without_a_legacy_path(self) -> None:
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
        self.assertNotIn(result.working_tree, transaction.snapshots)
        self.assertNotIn(repo.legacy_target, transaction.snapshots)
        self.assertFalse(os.path.lexists(repo.legacy_target))
        self.assertEqual(changes.changed_paths, tuple(sorted(changes.changed_paths, key=lambda path: path.as_posix())))

    def test_rejects_an_existing_checkout_beneath_a_symlinked_shared_parent(self) -> None:
        repo = self.repository()
        outside_shared = self.root / "outside-shared"
        outside_checkout = outside_shared / repo.name
        self.clone(outside_checkout)
        outside_head = run_git("rev-parse", "HEAD", cwd=outside_checkout)
        source_head = self.remote_head()
        self.data_root.mkdir(parents=True)
        repo.target.parent.symlink_to(outside_shared, target_is_directory=True)
        (outside_checkout / "entry.md").write_text("outside\n", encoding="utf-8")

        with self.assertRaises(RepositoryError) as caught:
            synchronize_remote(repo, self.auth)

        self.assertEqual(self.remote_head(), source_head)
        self.assertEqual(run_git("rev-parse", "HEAD", cwd=outside_checkout), outside_head)
        self.assert_hidden_in_bootstrap_error_graph(caught.exception, "fixture-token")

    def test_rejects_an_existing_legacy_checkout_beneath_a_symlinked_parent(self) -> None:
        repo = self.repository()
        outside_core = self.root / "outside-core"
        outside_checkout = outside_core / repo.name
        self.clone(outside_checkout)
        outside_head = run_git("rev-parse", "HEAD", cwd=outside_checkout)
        source_head = self.remote_head()
        self.data_root.mkdir(parents=True)
        repo.legacy_target.parent.symlink_to(outside_core, target_is_directory=True)

        with self.assertRaises(RepositoryError) as caught:
            synchronize_remote(repo, self.auth)

        self.assertEqual(self.remote_head(), source_head)
        self.assertEqual(run_git("rev-parse", "HEAD", cwd=outside_checkout), outside_head)
        self.assert_hidden_in_bootstrap_error_graph(caught.exception, "fixture-token")

    def test_rejects_a_symlinked_lock_parent_before_creating_a_lock(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        outside_locks = self.root / "outside-locks"
        outside_locks.mkdir()
        (self.data_root / "locks").symlink_to(outside_locks, target_is_directory=True)

        with self.assertRaises(RepositoryError) as caught:
            synchronize_remote(repo, self.auth)

        self.assertEqual(tuple(outside_locks.iterdir()), ())
        self.assert_hidden_in_bootstrap_error_graph(caught.exception, "fixture-token")

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

    def test_read_only_same_commit_is_an_exact_unchanged_result(self) -> None:
        repo = self.repository(mode="read-only")
        self.clone(repo.target)
        expected = run_git("rev-parse", "HEAD", cwd=repo.target)

        result = synchronize_remote(repo, self.auth)

        self.assertEqual(result, RemoteSyncResult("lifelog", expected, False, repo.target))

    def test_read_write_unchanged_sync_does_not_commit_or_push(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        expected = run_git("rev-parse", "HEAD", cwd=repo.target)
        commit_count = run_git("rev-list", "--count", "HEAD", cwd=repo.target)

        result = synchronize_remote(repo, self.auth)

        self.assertEqual(result, RemoteSyncResult("lifelog", expected, False, repo.target))
        self.assertEqual(run_git("rev-list", "--count", "HEAD", cwd=repo.target), commit_count)
        self.assertEqual(self.remote_head(), expected)

    def test_declared_remote_credential_named_knowledge_remains_writable(self) -> None:
        repo = self.repository()
        knowledge = self.seed / "authentication-guide.md"
        knowledge.write_text("declared remote knowledge\n", encoding="utf-8")
        run_git("add", knowledge.name, cwd=self.seed)
        run_git("commit", "-m", "add declared knowledge", cwd=self.seed)
        run_git("push", "origin", "main", cwd=self.seed)
        self.clone(repo.target)
        expected = run_git("rev-parse", "HEAD", cwd=repo.target)

        result = synchronize_remote(repo, self.auth)

        self.assertEqual(result, RemoteSyncResult("lifelog", expected, False, repo.target))
        (repo.target / knowledge.name).write_text("local credential change\n", encoding="utf-8")
        updated = synchronize_remote(repo, self.auth)
        self.assertTrue(updated.pushed)
        self.assertEqual(run_git("rev-parse", "HEAD", cwd=repo.target), self.remote_head())

    def test_read_write_rolls_back_failed_publication_and_retries_dirty_changes(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        (repo.target / "entry.md").write_text("entry\n", encoding="utf-8")

        result = synchronize_remote(repo, self.auth)

        self.assertTrue(result.pushed)
        self.assertEqual(run_git("rev-parse", "HEAD", cwd=repo.target), self.remote_head())
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
        self.assertTrue((repo.target / "retry.md").is_file())
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

    def test_read_write_rejects_external_hardlinks_before_committing_or_pushing(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        source_head = self.remote_head()
        outside_secret = self.data_root / ".env"
        outside_secret.parent.mkdir(parents=True, exist_ok=True)
        outside_secret.write_text("external-hardlink-secret-marker\n", encoding="utf-8")
        os.link(outside_secret, repo.target / "notes.md")

        with self.assertRaises(RepositoryError) as caught:
            synchronize_remote(repo, self.auth)

        self.assertEqual(self.remote_head(), source_head)
        self.assert_hidden_in_bootstrap_error_graph(
            caught.exception,
            "external-hardlink-secret-marker",
            "fixture-token",
        )

    def test_read_write_rejects_external_hardlinks_in_a_prior_unpushed_commit(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        source_head = self.remote_head()
        outside_secret = self.data_root / ".env"
        outside_secret.parent.mkdir(parents=True, exist_ok=True)
        outside_secret.write_text("prior-hardlink-secret-marker\n", encoding="utf-8")
        os.link(outside_secret, repo.target / "notes.md")
        run_git("add", "notes.md", cwd=repo.target)
        run_git("commit", "-m", "prior hardlink", cwd=repo.target)

        with self.assertRaises(RepositoryError) as caught:
            synchronize_remote(repo, self.auth)

        self.assertEqual(self.remote_head(), source_head)
        self.assert_hidden_in_bootstrap_error_graph(
            caught.exception,
            "prior-hardlink-secret-marker",
            "fixture-token",
        )

    def test_read_write_rejects_deleted_external_hardlinks_in_unpushed_history(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        source_head = self.remote_head()
        outside_secret = self.data_root / ".env"
        outside_secret.parent.mkdir(parents=True, exist_ok=True)
        outside_secret.write_text("deleted-hardlink-secret-marker\n", encoding="utf-8")
        linked = repo.target / "notes.md"
        os.link(outside_secret, linked)
        run_git("add", "notes.md", cwd=repo.target)
        run_git("commit", "-m", "add prior hardlink", cwd=repo.target)
        linked.unlink()
        run_git("add", "-A", cwd=repo.target)
        run_git("commit", "-m", "delete prior hardlink", cwd=repo.target)

        with self.assertRaises(RepositoryError) as caught:
            synchronize_remote(repo, self.auth)

        self.assertEqual(self.remote_head(), source_head)
        self.assert_hidden_in_bootstrap_error_graph(
            caught.exception,
            "deleted-hardlink-secret-marker",
            "fixture-token",
        )

    def test_read_write_rejects_unpushed_history_hidden_by_replace_refs(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        source_head = self.remote_head()
        hidden = repo.target / "notes.md"
        hidden.write_text("replace-ref-secret-marker\n", encoding="utf-8")
        run_git("add", "notes.md", cwd=repo.target)
        run_git("commit", "-m", "add hidden history", cwd=repo.target)
        hidden.unlink()
        run_git("add", "-A", cwd=repo.target)
        run_git("commit", "-m", "hide prior history", cwd=repo.target)
        replaced_head = run_git("rev-parse", "HEAD", cwd=repo.target)
        run_git("replace", replaced_head, source_head, cwd=repo.target)
        (repo.target / "entry.md").write_text("entry\n", encoding="utf-8")

        with self.assertRaises(RepositoryError) as caught:
            synchronize_remote(repo, self.auth)

        self.assertEqual(self.remote_head(), source_head)
        self.assert_hidden_in_bootstrap_error_graph(
            caught.exception,
            "replace-ref-secret-marker",
            "fixture-token",
        )

    def test_rejects_replace_refs_even_when_the_checkout_appears_unchanged(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        source_head = self.remote_head()
        run_git("commit", "--allow-empty", "-m", "replacement object", cwd=repo.target)
        replacement = run_git("rev-parse", "HEAD", cwd=repo.target)
        run_git("reset", "--hard", source_head, cwd=repo.target)
        run_git("replace", source_head, replacement, cwd=repo.target)

        with self.assertRaises(RepositoryError) as caught:
            synchronize_remote(repo, self.auth)

        self.assertEqual(self.remote_head(), source_head)
        self.assert_hidden_in_bootstrap_error_graph(caught.exception, "fixture-token")

    def test_read_write_allows_hardlinks_fully_contained_in_the_checkout(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        first = repo.target / "first.md"
        second = repo.target / "second.md"
        first.write_text("shared inode\n", encoding="utf-8")
        os.link(first, second)

        result = synchronize_remote(repo, self.auth)

        self.assertTrue(result.pushed)
        self.assertEqual(self.remote_head(), run_git("rev-parse", "HEAD", cwd=repo.target))

    def test_read_write_rebases_onto_the_declared_remote_commit_before_pushing(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        (repo.target / "local.md").write_text("local\n", encoding="utf-8")
        self.advance_remote("remote\n")

        result = synchronize_remote(repo, self.auth)

        self.assertTrue(result.pushed)
        self.assertEqual((repo.target / "README.md").read_text(encoding="utf-8"), "remote\n")
        self.assertEqual((repo.target / "local.md").read_text(encoding="utf-8"), "local\n")

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
        self.assertFalse((repo.target / ".git" / "rebase-merge").exists())
        self.assertFalse((repo.target / ".git" / "rebase-apply").exists())

    def test_rebase_abort_failure_is_a_fixed_repository_error(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        (repo.target / "README.md").write_text("local abort marker\n", encoding="utf-8")
        self.advance_remote("remote abort marker\n")
        real_runner = repositories_module._run_git_bytes
        abort_attempts: list[int] = []

        def fail_abort(
            arguments: tuple[str, ...],
            cwd: Path,
            environment: dict[str, str],
            *,
            max_output_bytes: int,
        ) -> bytes | None:
            if arguments == ("rebase", "--abort"):
                abort_attempts.append(1)
                return None
            return real_runner(arguments, cwd, environment, max_output_bytes=max_output_bytes)

        with mock.patch.object(repositories_module, "_run_git_bytes", side_effect=fail_abort):
            with self.assertRaisesRegex(RepositoryError, "could not synchronize shared repository") as caught:
                synchronize_remote(repo, self.auth)

        self.assertTrue(
            (repo.target / ".git" / "rebase-merge").exists()
            or (repo.target / ".git" / "rebase-apply").exists()
        )
        self.assertEqual(abort_attempts, [1])
        self.assert_hidden_in_bootstrap_error_graph(caught.exception, "abort marker", "fixture-token")
        run_git("rebase", "--abort", cwd=repo.target)

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

    def test_rejects_pushurl_before_it_can_redirect_a_real_push(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        redirected = self.root / "pushurl-secret-marker.git"
        run_git("clone", "--bare", str(self.remote), str(redirected))
        run_git("remote", "set-url", "--add", "--push", "origin", str(redirected), cwd=repo.target)
        (repo.target / "entry.md").write_text("entry\n", encoding="utf-8")
        source_head = self.remote_head()
        redirected_head = self.remote_head(redirected)

        with self.assertRaises(RepositoryError) as caught:
            synchronize_remote(repo, self.auth)

        self.assertEqual(self.remote_head(), source_head)
        self.assertEqual(self.remote_head(redirected), redirected_head)
        self.assert_hidden_in_bootstrap_error_graph(caught.exception, "pushurl-secret-marker", "fixture-token")

    def test_rejects_local_insteadof_and_pushinsteadof_rewrites_without_exposing_values(self) -> None:
        for key in ("insteadOf", "pushInsteadOf"):
            with self.subTest(key=key):
                repo = self.repository()
                if repo.target.exists():
                    shutil.rmtree(repo.target)
                self.clone(repo.target)
                redirected = self.root / f"{key.casefold()}-secret-marker.git"
                run_git("clone", "--bare", str(self.remote), str(redirected))
                run_git("config", "--local", f"url.{redirected}.{key}", str(self.remote), cwd=repo.target)
                (repo.target / f"{key}.md").write_text("redirect\n", encoding="utf-8")

                with self.assertRaises(RepositoryError) as caught:
                    synchronize_remote(repo, self.auth)

                self.assert_hidden_in_bootstrap_error_graph(caught.exception, "secret-marker", "fixture-token")

    def test_rejects_local_filter_commands_before_they_can_read_the_github_token(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        marker = self.root / "filter-token-marker"
        command = f"sh -c 'printf %s \"$HERMES_BOOTSTRAP_GITHUB_TOKEN\" > {marker}'"
        run_git("config", "--local", "filter.capture.clean", command, cwd=repo.target)
        (repo.target / ".gitattributes").write_text("*.md filter=capture\n", encoding="utf-8")
        (repo.target / "entry.md").write_text("entry\n", encoding="utf-8")

        with self.assertRaises(RepositoryError) as caught:
            synchronize_remote(repo, self.auth)

        self.assertFalse(marker.exists())
        self.assert_hidden_in_bootstrap_error_graph(caught.exception, "fixture-token")

    def test_rejects_an_external_core_worktree_before_staging_or_pushing(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        source_head = self.remote_head()
        outside = self.root / "external-worktree"
        outside.mkdir()
        (outside / "notes.md").write_text("external-worktree-secret-marker\n", encoding="utf-8")
        run_git("config", "--local", "core.worktree", str(outside), cwd=repo.target)

        with self.assertRaises(RepositoryError) as caught:
            synchronize_remote(repo, self.auth)

        self.assertEqual(self.remote_head(), source_head)
        self.assert_hidden_in_bootstrap_error_graph(
            caught.exception,
            "external-worktree-secret-marker",
            "fixture-token",
        )

    def test_rejects_worktree_scoped_config_before_authenticated_git(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        run_git("config", "--local", "extensions.worktreeConfig", "true", cwd=repo.target)
        run_git("config", "--worktree", "http.proxy", "http://127.0.0.1:9", cwd=repo.target)

        with self.assertRaises(RepositoryError) as caught:
            synchronize_remote(repo, self.auth)

        self.assert_hidden_in_bootstrap_error_graph(caught.exception, "fixture-token")

    def test_rejects_local_http_transport_overrides_before_fetching(self) -> None:
        for key, value in (("http.proxy", "http://127.0.0.1:9"), ("http.sslVerify", "false")):
            with self.subTest(key=key):
                repo = self.repository()
                if repo.target.exists():
                    shutil.rmtree(repo.target)
                self.clone(repo.target)
                run_git("config", "--local", key, value, cwd=repo.target)

                with self.assertRaises(RepositoryError) as caught:
                    synchronize_remote(repo, self.auth)

                self.assert_hidden_in_bootstrap_error_graph(caught.exception, "fixture-token")

    def test_explicit_destination_ignores_remote_transport_overrides(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        marker = self.root / "transport-override-marker"
        override = self.root / "transport-override"
        override.write_text(f"#!/bin/sh\nprintf invoked > '{marker}'\nexit 1\n", encoding="utf-8")
        override.chmod(0o700)
        run_git("config", "--local", "remote.origin.uploadpack", str(override), cwd=repo.target)
        run_git("config", "--local", "remote.origin.receivepack", str(override), cwd=repo.target)
        (repo.target / "explicit.md").write_text("explicit\n", encoding="utf-8")

        result = synchronize_remote(repo, self.auth)

        self.assertTrue(result.pushed)
        self.assertFalse(marker.exists())

    def test_prior_unpushed_forbidden_history_is_rejected_even_when_current_tree_deleted_it(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        source_head = self.remote_head()
        (repo.target / ".env").write_text("forbidden-content-marker\n", encoding="utf-8")
        run_git("add", ".env", cwd=repo.target)
        run_git("commit", "-m", "add forbidden", cwd=repo.target)
        (repo.target / ".env").unlink()
        run_git("add", "-A", cwd=repo.target)
        run_git("commit", "-m", "remove forbidden", cwd=repo.target)

        with self.assertRaises(RepositoryError) as caught:
            synchronize_remote(repo, self.auth)

        self.assertEqual(self.remote_head(), source_head)
        self.assert_hidden_in_bootstrap_error_graph(caught.exception, "forbidden-content-marker", "fixture-token")

    def test_preexisting_staged_gitlink_is_rejected(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        nested = repo.target / "nested"
        self.create_nested_repository(nested)
        run_git("add", "nested", cwd=repo.target)
        source_head = self.remote_head()

        with self.assertRaises(RepositoryError):
            synchronize_remote(repo, self.auth)

        self.assertEqual(self.remote_head(), source_head)

    def test_preexisting_committed_gitlink_is_rejected(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        nested = repo.target / "nested"
        self.create_nested_repository(nested)
        run_git("add", "nested", cwd=repo.target)
        run_git("commit", "-m", "nested gitlink", cwd=repo.target)
        source_head = self.remote_head()

        with self.assertRaises(RepositoryError):
            synchronize_remote(repo, self.auth)

        self.assertEqual(self.remote_head(), source_head)

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

    def test_forbidden_path_race_after_preflight_restores_the_original_index(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        (repo.target / "allowed.md").write_text("allowed\n", encoding="utf-8")
        before_index = (repo.target / ".git" / "index").read_bytes()
        real_require = repositories_module._require_git_success

        def inject_before_add(
            arguments: tuple[str, ...], checkout: Path, environment: dict[str, str]
        ) -> None:
            if arguments == ("add", "-A", "--", "."):
                (checkout / ".env").write_text("raced-secret-marker\n", encoding="utf-8")
            real_require(arguments, checkout, environment)

        with mock.patch.object(repositories_module, "_require_git_success", side_effect=inject_before_add):
            with self.assertRaises(RepositoryError) as caught:
                synchronize_remote(repo, self.auth)

        self.assertEqual((repo.target / ".git" / "index").read_bytes(), before_index)
        self.assertEqual(run_git_bytes("diff", "--cached", "--name-only", "-z", cwd=repo.target), b"")
        self.assert_hidden_in_bootstrap_error_graph(caught.exception, "raced-secret-marker", "fixture-token")

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

    def test_lock_contention_from_a_second_process_reports_only_the_lock_path(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        lock = self.data_root / "locks" / "repositories" / "lifelog.lock"
        lock.parent.mkdir(parents=True, exist_ok=True)
        ready = self.root / "lock-ready"
        script = (
            "import fcntl, pathlib, sys\n"
            "handle = open(sys.argv[1], 'a+')\n"
            "fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)\n"
            "pathlib.Path(sys.argv[2]).write_text('ready')\n"
            "sys.stdin.buffer.read(1)\n"
        )
        process = subprocess.Popen(
            (sys.executable, "-c", script, str(lock), str(ready)),
            stdin=subprocess.PIPE,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        try:
            for _ in range(200):
                if ready.exists():
                    break
                if process.poll() is not None:
                    self.fail("lock holder exited before acquiring the lock")
                time.sleep(0.01)
            else:
                self.fail("lock holder did not acquire the lock")

            with self.assertRaises(RepositoryError) as caught:
                synchronize_remote(repo, self.auth)
            self.assertEqual(str(caught.exception), str(lock))
        finally:
            if process.stdin is not None:
                process.stdin.write(b"x")
                process.stdin.close()
            process.wait(timeout=5)

    def test_askpass_unlink_failure_turns_an_unchanged_success_into_a_fixed_error(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        real_unlink = Path.unlink

        def fail_askpass_unlink(path: Path, *arguments: object, **keywords: object) -> None:
            if path.name.startswith("askpass-"):
                raise OSError("askpass-cleanup-secret-marker")
            real_unlink(path, *arguments, **keywords)

        with mock.patch.object(Path, "unlink", new=fail_askpass_unlink):
            with self.assertRaisesRegex(RepositoryError, "could not clean private repository resources") as caught:
                synchronize_remote(repo, self.auth)

        leftovers = list(repo.target.parent.glob("askpass-*"))
        self.assertTrue(leftovers)
        self.assert_hidden_in_bootstrap_error_graph(
            caught.exception, "askpass-cleanup-secret-marker", "fixture-token", str(self.remote)
        )
        for leftover in leftovers:
            leftover.unlink()

    def test_failed_private_stage_cleanup_failure_is_fixed_and_redacted(self) -> None:
        repo = replace(self.repository(), ref="missing")
        real_rmtree = shutil.rmtree

        def fail_stage_cleanup(path: Path, *arguments: object, **keywords: object) -> None:
            if Path(path).name.startswith(".hermes-repository-"):
                raise OSError("stage-cleanup-content-marker")
            real_rmtree(path, *arguments, **keywords)

        with mock.patch.object(repositories_module.shutil, "rmtree", side_effect=fail_stage_cleanup):
            with self.assertRaisesRegex(RepositoryError, "could not clean private repository resources") as caught:
                synchronize_remote(repo, self.auth)

        leftovers = list(repo.target.parent.glob(".hermes-repository-*"))
        self.assertTrue(leftovers)
        self.assert_hidden_in_bootstrap_error_graph(
            caught.exception, "stage-cleanup-content-marker", "fixture-token", str(self.remote)
        )
        for leftover in leftovers:
            real_rmtree(leftover)

    def test_synchronize_rejects_two_real_paths_before_committing_or_pushing_canonical_changes(
        self,
    ) -> None:
        repo = self.repository()
        self.clone(repo.target)
        self.clone(repo.legacy_target)
        (repo.target / "local.md").write_text("local\n", encoding="utf-8")
        canonical_head = run_git("rev-parse", "HEAD", cwd=repo.target)
        canonical_status = run_git_bytes(
            "status", "--porcelain=v1", "-z", "--untracked-files=all", cwd=repo.target
        )
        remote_head = self.remote_head()

        with self.assertRaises(MigrationError):
            synchronize_remote(repo, self.auth)

        self.assertEqual(run_git("rev-parse", "HEAD", cwd=repo.target), canonical_head)
        self.assertEqual(
            run_git_bytes(
                "status", "--porcelain=v1", "-z", "--untracked-files=all", cwd=repo.target
            ),
            canonical_status,
        )
        self.assertEqual(self.remote_head(), remote_head)

    def test_apply_migrates_legacy_rejects_two_real_paths_and_is_idempotent(self) -> None:
        repo = self.repository()
        self.clone(repo.legacy_target)
        result = synchronize_remote(repo, self.auth)
        transaction = RecordingTransaction()
        apply_shared_working_tree(repo, result, transaction)
        self.assertTrue(repo.target.is_dir())
        self.assertFalse(os.path.lexists(repo.legacy_target))
        self.assertEqual(apply_shared_working_tree(repo, result, RecordingTransaction()).changed_paths, ())

        self.clone(repo.legacy_target)
        with self.assertRaises(MigrationError):
            apply_shared_working_tree(repo, result, RecordingTransaction())

    def test_apply_removes_an_old_compatibility_link_and_rollback_restores_it(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        assert repo.legacy_target is not None
        repo.legacy_target.parent.mkdir(parents=True)
        repo.legacy_target.symlink_to("../shared/lifelog")
        result = synchronize_remote(repo, self.auth)
        tx = Transaction.begin(self.data_root)

        changes = apply_shared_working_tree(repo, result, tx)

        self.assertIn(repo.legacy_target, changes.changed_paths)
        self.assertFalse(os.path.lexists(repo.legacy_target))
        tx.rollback()
        self.assertTrue(repo.legacy_target.is_symlink())
        self.assertEqual(os.readlink(repo.legacy_target), "../shared/lifelog")

    def test_apply_removes_empty_legacy_and_runtime_requires_canonical_checkout(self) -> None:
        repo = self.repository()
        repo.legacy_target.parent.mkdir(parents=True)
        repo.legacy_target.mkdir()
        result = synchronize_remote(repo, self.auth)
        apply_shared_working_tree(repo, result, RecordingTransaction())
        self.assertFalse(os.path.lexists(repo.legacy_target))
        manifest = BootstrapManifest(1, self.data_root, (), None, (), (repo,))  # type: ignore[arg-type]
        synced = synchronize_named_repository("lifelog", manifest, self.auth, require_canonical=True)
        self.assertEqual(synced.working_tree, repo.target)
        shutil.rmtree(repo.target)
        with self.assertRaises(RepositoryError):
            synchronize_named_repository("lifelog", manifest, self.auth, require_canonical=True)

    def test_apply_rejects_a_source_swapped_after_record_move_before_touching_canonical(self) -> None:
        repo = self.repository()
        result = synchronize_remote(repo, self.auth)
        transaction = SwappingTransaction()

        with self.assertRaises(RepositoryError):
            apply_shared_working_tree(repo, result, transaction)

        self.assertFalse(repo.target.exists())
        self.assertIsNotNone(transaction.held)
        self.assertTrue((transaction.held / ".git").is_dir())

    def test_apply_preserves_a_target_created_at_the_publication_boundary(self) -> None:
        repo = self.repository()
        result = synchronize_remote(repo, self.auth)
        transaction = RecordingTransaction()
        raced_identity: tuple[int, int] | None = None

        def race_before_publish(source_parent: int, source: str, target_parent: int, target: str) -> None:
            nonlocal raced_identity
            repo.target.mkdir()
            metadata = repo.target.stat()
            raced_identity = (metadata.st_dev, metadata.st_ino)
            transaction_module._rename_noreplace(source_parent, source, target_parent, target)

        with mock.patch.object(
            repositories_module,
            "_rename_noreplace",
            create=True,
            side_effect=race_before_publish,
        ):
            with self.assertRaises(RepositoryError):
                apply_shared_working_tree(repo, result, transaction)

        self.assertIsNotNone(raced_identity)
        self.assertEqual((repo.target.stat().st_dev, repo.target.stat().st_ino), raced_identity)
        self.assertTrue((result.working_tree / ".git").is_dir())
        self.assertEqual(transaction.moves, [(result.working_tree, repo.target)])

    def test_apply_preserves_an_existing_empty_canonical_target(self) -> None:
        repo = self.repository()
        result = synchronize_remote(repo, self.auth)
        repo.target.mkdir()
        initial_metadata = repo.target.stat()
        expected_identity = (initial_metadata.st_dev, initial_metadata.st_ino)

        with self.assertRaises(RepositoryError):
            apply_shared_working_tree(repo, result, RecordingTransaction())

        self.assertEqual((repo.target.stat().st_dev, repo.target.stat().st_ino), expected_identity)
        self.assertTrue((result.working_tree / ".git").is_dir())

    def test_apply_can_retry_after_a_later_transaction_rollback(self) -> None:
        repo = self.repository()
        result = synchronize_remote(repo, self.auth)
        first = RecordingTransaction()
        apply_shared_working_tree(repo, result, first)
        os.replace(repo.target, result.working_tree)

        changes = apply_shared_working_tree(repo, result, RecordingTransaction())

        self.assertIn(repo.target, changes.changed_paths)
        self.assertEqual(run_git("rev-parse", "HEAD", cwd=repo.target), result.commit)
        self.assertFalse(os.path.lexists(repo.legacy_target))

    def test_real_legacy_migration_rolls_back_with_identity_and_can_retry(self) -> None:
        repo = self.repository()
        assert repo.legacy_target is not None
        self.clone(repo.legacy_target)
        run_git(
            "config",
            "--local",
            "hermes.fixture-migration-id",
            "legacy-checkout-only",
            cwd=repo.legacy_target,
        )
        metadata = repo.legacy_target.stat()
        identity = (metadata.st_dev, metadata.st_ino)
        result = synchronize_remote(repo, self.auth)
        tx = Transaction.begin(self.data_root)

        apply_shared_working_tree(repo, result, tx)
        self.assertTrue(repo.target.is_dir())
        self.assertFalse(os.path.lexists(repo.legacy_target))
        tx.rollback()

        self.assertTrue(repo.legacy_target.is_dir())
        self.assertFalse(repo.legacy_target.is_symlink())
        self.assertEqual(
            (repo.legacy_target.stat().st_dev, repo.legacy_target.stat().st_ino),
            identity,
        )
        self.assertEqual(
            run_git(
                "config",
                "--local",
                "--get",
                "hermes.fixture-migration-id",
                cwd=repo.legacy_target,
            ),
            "legacy-checkout-only",
        )
        self.assertFalse(os.path.lexists(repo.target))

        retry = synchronize_remote(repo, self.auth)
        retry_tx = Transaction.begin(self.data_root)
        apply_shared_working_tree(repo, retry, retry_tx)
        retry_tx.commit()

        self.assertTrue(repo.target.is_dir())
        self.assertFalse(os.path.lexists(repo.legacy_target))
        self.assertEqual(
            run_git(
                "config",
                "--local",
                "--get",
                "hermes.fixture-migration-id",
                cwd=repo.target,
            ),
            "legacy-checkout-only",
        )

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

    @unittest.skipUnless(os.name == "posix", "requires byte-preserving POSIX paths")
    def test_read_write_sync_preserves_an_undecodable_filename(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        raw_name = b"entry-\xff.md"
        descriptor = os.open(os.fsencode(repo.target) + b"/" + raw_name, os.O_WRONLY | os.O_CREAT, 0o600)
        try:
            os.write(descriptor, b"surrogateescape\n")
        finally:
            os.close(descriptor)

        result = synchronize_remote(repo, self.auth)

        self.assertTrue(result.pushed)
        tree = run_git_bytes("ls-tree", "-r", "-z", "--name-only", "HEAD", cwd=repo.target)
        self.assertIn(raw_name + b"\0", tree)

    def test_read_write_accepts_valid_nul_status_larger_than_four_kibibytes(self) -> None:
        repo = self.repository()
        self.clone(repo.target)
        for index in range(240):
            (repo.target / f"entry-{index:03d}-with-a-bounded-name.md").write_text("entry\n", encoding="utf-8")
        status = run_git_bytes("status", "--porcelain=v1", "-z", "--untracked-files=all", cwd=repo.target)
        self.assertGreater(len(status), 4096)

        result = synchronize_remote(repo, self.auth)

        self.assertTrue(result.pushed)

    def test_index_validation_accepts_a_bounded_tree_larger_than_512_kibibytes(self) -> None:
        record = b"100644 " + (b"a" * 40) + b" 0\tknowledge/entry-with-a-bounded-name.md\0"
        index = record * 7000
        self.assertGreater(len(index), 512 * 1024)

        def bounded_runner(
            arguments: tuple[str, ...],
            _cwd: Path,
            _environment: dict[str, str],
            *,
            max_output_bytes: int,
        ) -> bytes | None:
            self.assertEqual(arguments, ("ls-files", "--stage", "-z"))
            return index if len(index) <= max_output_bytes else None

        with mock.patch.object(repositories_module, "_run_git_bytes", side_effect=bounded_runner):
            repositories_module._validate_index(self.root, {})


if __name__ == "__main__":
    unittest.main()
