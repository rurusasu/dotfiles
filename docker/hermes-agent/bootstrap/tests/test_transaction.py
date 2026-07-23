"""Durable transaction journal coverage."""

from __future__ import annotations

import json
import os
import shutil
import stat
import tempfile
import unittest
from contextlib import ExitStack
from pathlib import Path
from unittest import mock

from hermes_bootstrap.errors import ApplyError, RollbackError
from hermes_bootstrap.transaction import Transaction
import hermes_bootstrap.transaction as transaction_module


class TransactionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name) / "data"
        self.root.mkdir()

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def journal_paths(self) -> list[Path]:
        return sorted((self.root / ".bootstrap" / "transactions").glob("*/journal.json"))

    def journal(self) -> tuple[Path, dict[str, object]]:
        paths = self.journal_paths()
        self.assertEqual(len(paths), 1)
        return paths[0], json.loads(paths[0].read_text(encoding="utf-8"))

    def crash(self, tx: Transaction) -> None:
        tx._release_lock()

    def make_private_store(self, root: Path) -> Path:
        bootstrap = root / ".bootstrap"
        bootstrap.mkdir(mode=0o700)
        store = bootstrap / "transactions"
        store.mkdir(mode=0o700)
        return store

    def private_recovery_hierarchy(
        self,
        root: Path,
        *,
        bootstrap_mode: int = 0o700,
    ) -> tuple[dict[str, Path], Path]:
        source = root / "trust-boundary-secret"
        nested = source / "nested"
        nested.mkdir(mode=0o700, parents=True)
        (nested / "file").write_text("before", encoding="utf-8")
        source.chmod(0o700)
        bootstrap = root / ".bootstrap"
        bootstrap.mkdir(mode=bootstrap_mode)
        bootstrap.chmod(bootstrap_mode)
        tx = Transaction.begin(root)
        tx.snapshot(source)
        journal_path = next((root / ".bootstrap" / "transactions").glob("*/journal.json"))
        journal = json.loads(journal_path.read_text(encoding="utf-8"))
        journal["status"] = "committed"
        journal_path.write_text(json.dumps(journal), encoding="utf-8")
        self.crash(tx)
        backup = journal_path.parent / journal["entries"][0]["backup"]
        return (
            {
                "bootstrap": bootstrap,
                "store": root / ".bootstrap" / "transactions",
                "journal": journal_path.parent,
                "backup": backup,
                "nested-backup": backup / "nested",
            },
            journal_path,
        )

    def reported_owner(self, path: Path, owner: int) -> ExitStack:
        identity = (path.lstat().st_dev, path.lstat().st_ino)
        original_lstat = os.lstat
        original_stat = os.stat
        original_fstat = os.fstat

        def change_owner(info: os.stat_result) -> os.stat_result:
            if (info.st_dev, info.st_ino) != identity:
                return info
            values = list(info)
            values[4] = owner
            return os.stat_result(values)

        def lstat(*args: object, **kwargs: object) -> os.stat_result:
            return change_owner(original_lstat(*args, **kwargs))

        def stat_path(*args: object, **kwargs: object) -> os.stat_result:
            return change_owner(original_stat(*args, **kwargs))

        def fstat(*args: object, **kwargs: object) -> os.stat_result:
            return change_owner(original_fstat(*args, **kwargs))

        stack = ExitStack()
        stack.enter_context(mock.patch.object(transaction_module.os, "lstat", side_effect=lstat))
        stack.enter_context(mock.patch.object(transaction_module.os, "stat", side_effect=stat_path))
        stack.enter_context(mock.patch.object(transaction_module.os, "fstat", side_effect=fstat))
        return stack

    def test_snapshot_absent_removes_new_target_on_rollback(self) -> None:
        path = self.root / "new.txt"
        tx = Transaction.begin(self.root)

        tx.snapshot(path)
        path.write_text("new", encoding="utf-8")
        tx.rollback()

        self.assertFalse(os.path.lexists(path))
        self.assertEqual(self.journal_paths(), [])

    def test_directory_reservation_rollback_removes_only_the_reserved_identity(
        self,
    ) -> None:
        profiles = self.root / "profiles"
        profiles.mkdir()
        target = profiles / "rick"
        tx = Transaction.begin(self.root)

        self.assertTrue(tx.reserve_directory(target))
        shutil.rmtree(target)
        target.mkdir()
        (target / "external.txt").write_bytes(b"external\n")
        external_identity = (target.lstat().st_dev, target.lstat().st_ino)

        tx.rollback()

        self.assertEqual(
            (target.lstat().st_dev, target.lstat().st_ino),
            external_identity,
        )
        self.assertEqual((target / "external.txt").read_bytes(), b"external\n")
        self.assertEqual(self.journal_paths(), [])

    def test_directory_reservation_recovery_preserves_a_replacement_identity(
        self,
    ) -> None:
        profiles = self.root / "profiles"
        profiles.mkdir()
        target = profiles / "rick"
        tx = Transaction.begin(self.root)

        self.assertTrue(tx.reserve_directory(target))
        shutil.rmtree(target)
        target.mkdir()
        (target / "external.txt").write_bytes(b"external after crash\n")
        replacement_identity = (target.lstat().st_dev, target.lstat().st_ino)
        self.crash(tx)

        Transaction.recover_if_needed(self.root)

        self.assertEqual(
            (target.lstat().st_dev, target.lstat().st_ino),
            replacement_identity,
        )
        self.assertEqual(
            (target / "external.txt").read_bytes(),
            b"external after crash\n",
        )
        self.assertEqual(self.journal_paths(), [])

    def test_directory_reservation_commit_removes_the_private_marker(self) -> None:
        profiles = self.root / "profiles"
        profiles.mkdir()
        target = profiles / "rick"
        tx = Transaction.begin(self.root)

        self.assertTrue(tx.reserve_directory(target))
        self.assertTrue((target / ".bootstrap-reservation").is_file())

        tx.commit()

        self.assertTrue(target.is_dir())
        self.assertFalse((target / ".bootstrap-reservation").exists())
        self.assertEqual(self.journal_paths(), [])

    def test_nonrecursive_directory_reservation_preserves_an_external_child(
        self,
    ) -> None:
        profiles = self.root / "profiles"
        tx = Transaction.begin(self.root)

        self.assertTrue(tx.reserve_directory(profiles, remove_tree=False))
        external = profiles / "rick"
        external.mkdir()
        (external / "config.yaml").write_bytes(b"external\n")

        tx.rollback()

        self.assertEqual(
            (external / "config.yaml").read_bytes(),
            b"external\n",
        )
        self.assertFalse((profiles / ".bootstrap-reservation").exists())
        self.assertEqual(self.journal_paths(), [])

    def test_directory_reservation_crash_recovery_removes_the_owned_tree(
        self,
    ) -> None:
        profiles = self.root / "profiles"
        profiles.mkdir()
        target = profiles / "rick"
        tx = Transaction.begin(self.root)

        self.assertTrue(tx.reserve_directory(target))
        (target / "config.yaml").write_bytes(b"transaction-owned\n")
        self.crash(tx)

        Transaction.recover_if_needed(self.root)

        self.assertFalse(target.exists())
        self.assertEqual(self.journal_paths(), [])

    def test_committed_directory_reservation_recovery_removes_only_the_marker(
        self,
    ) -> None:
        profiles = self.root / "profiles"
        profiles.mkdir()
        target = profiles / "rick"
        tx = Transaction.begin(self.root)
        self.assertTrue(tx.reserve_directory(target))
        (target / "config.yaml").write_bytes(b"committed\n")

        with mock.patch.object(
            transaction_module,
            "_failpoint",
            side_effect=lambda name: (
                (_ for _ in ()).throw(OSError())
                if name == "status-update"
                else None
            ),
        ):
            with self.assertRaises(ApplyError):
                tx.commit()
        self.crash(tx)

        Transaction.recover_if_needed(self.root)

        self.assertEqual((target / "config.yaml").read_bytes(), b"committed\n")
        self.assertFalse((target / ".bootstrap-reservation").exists())
        self.assertEqual(self.journal_paths(), [])

    def test_snapshot_only_journal_uses_schema_version_three(self) -> None:
        tx = Transaction.begin(self.root)

        _journal_path, journal = self.journal()
        self.assertEqual(journal["version"], 3)

        tx.rollback()

    def test_snapshot_regular_file_restores_bytes_and_executable_mode(self) -> None:
        path = self.root / "tool"
        path.write_bytes(b"before\x00")
        path.chmod(0o751)
        tx = Transaction.begin(self.root)

        tx.snapshot(path)
        path.write_bytes(b"after")
        path.chmod(0o600)
        tx.rollback()

        self.assertEqual(path.read_bytes(), b"before\x00")
        self.assertEqual(stat.S_IMODE(path.lstat().st_mode), 0o751)

    def test_snapshot_directory_restores_nested_files_links_and_metadata(self) -> None:
        path = self.root / "tree"
        nested = path / "nested"
        nested.mkdir(parents=True)
        (nested / "program").write_text("before", encoding="utf-8")
        (nested / "program").chmod(0o741)
        os.symlink("nested/program", path / "shortcut")
        tx = Transaction.begin(self.root)

        tx.snapshot(path)
        shutil.rmtree(path)
        path.mkdir()
        (path / "changed").write_text("after", encoding="utf-8")
        tx.rollback()

        self.assertEqual((nested / "program").read_text(encoding="utf-8"), "before")
        self.assertEqual(stat.S_IMODE((nested / "program").lstat().st_mode), 0o741)
        self.assertEqual(os.readlink(path / "shortcut"), "nested/program")

    def test_directory_snapshot_preserves_internal_hardlinks_without_linking_outside(self) -> None:
        tree = self.root / "tree"
        nested = tree / "nested"
        nested.mkdir(parents=True)
        first = tree / "first"
        second = nested / "second"
        first.write_text("shared", encoding="utf-8")
        os.link(first, second)
        outside = self.root.parent / "outside-link"
        os.link(first, outside)
        outside_inode = outside.stat().st_ino
        tx = Transaction.begin(self.root)

        tx.snapshot(tree)
        shutil.rmtree(tree)
        tree.mkdir()
        (tree / "changed").write_text("changed", encoding="utf-8")
        tx.rollback()

        self.assertEqual(first.read_text(encoding="utf-8"), "shared")
        self.assertEqual(first.stat().st_ino, second.stat().st_ino)
        self.assertNotEqual(first.stat().st_ino, outside_inode)
        self.assertEqual(outside.read_text(encoding="utf-8"), "shared")

    def test_directory_backup_is_private_and_recovery_restores_directory_metadata(self) -> None:
        tree = self.root / "tree"
        nested = tree / "nested"
        nested.mkdir(parents=True)
        tree.chmod(0o751)
        nested.chmod(0o710)
        (nested / "file").write_text("before", encoding="utf-8")
        tx = Transaction.begin(self.root)

        tx.snapshot(tree)
        journal_path, journal = self.journal()
        backup = journal_path.parent / journal["entries"][0]["backup"]
        for directory in (backup, backup / "nested"):
            info = directory.lstat()
            self.assertEqual(info.st_uid, os.geteuid())
            self.assertEqual(stat.S_IMODE(info.st_mode), 0o700)
        shutil.rmtree(tree)
        self.crash(tx)
        Transaction.recover_if_needed(self.root)

        self.assertEqual((nested / "file").read_text(encoding="utf-8"), "before")
        self.assertEqual(stat.S_IMODE(tree.lstat().st_mode), 0o751)
        self.assertEqual(stat.S_IMODE(nested.lstat().st_mode), 0o710)

    def test_directory_rollback_fails_closed_when_ownership_cannot_be_restored(self) -> None:
        tree = self.root / "tree"
        tree.mkdir()
        path = tree / "file"
        path.write_text("before", encoding="utf-8")
        tx = Transaction.begin(self.root)
        tx.snapshot(tree)
        path.write_text("after", encoding="utf-8")

        with mock.patch.object(transaction_module.os, "chown", side_effect=PermissionError):
            with self.assertRaises(RollbackError):
                tx.rollback()

        self.assertEqual(path.read_text(encoding="utf-8"), "after")
        self.assertTrue(self.journal_paths())

    def test_directory_backup_rejects_a_hardlink_escaping_the_transaction(self) -> None:
        tree = self.root / "tree"
        tree.mkdir(mode=0o700)
        path = tree / "file"
        path.write_text("before", encoding="utf-8")
        tx = Transaction.begin(self.root)
        tx.snapshot(tree)
        path.write_text("after", encoding="utf-8")
        journal_path, journal = self.journal()
        backup_file = journal_path.parent / journal["entries"][0]["backup"] / "file"
        escaped = self.root.parent / "escaped-backup-link"
        os.link(backup_file, escaped)
        self.crash(tx)

        with self.assertRaises(ApplyError):
            Transaction.recover_if_needed(self.root)
        self.assertEqual(path.read_text(encoding="utf-8"), "after")
        self.assertTrue(journal_path.exists())

    def test_snapshot_symlink_restores_link_text_without_following_it(self) -> None:
        target = self.root / "target"
        target.write_text("target", encoding="utf-8")
        path = self.root / "link"
        os.symlink("target", path)
        tx = Transaction.begin(self.root)

        tx.snapshot(path)
        path.unlink()
        os.symlink("other", path)
        tx.rollback()

        self.assertTrue(path.is_symlink())
        self.assertEqual(os.readlink(path), "target")
        self.assertEqual(target.read_text(encoding="utf-8"), "target")

    def test_snapshot_preserves_uid_gid_when_supported(self) -> None:
        path = self.root / "owned"
        path.write_text("before", encoding="utf-8")
        original = path.lstat()
        tx = Transaction.begin(self.root)

        tx.snapshot(path)
        path.write_text("after", encoding="utf-8")
        tx.rollback()

        restored = path.lstat()
        self.assertEqual((restored.st_uid, restored.st_gid), (original.st_uid, original.st_gid))

    def test_snapshot_rejects_special_files_and_unsafe_paths(self) -> None:
        fifo = self.root / "pipe"
        os.mkfifo(fifo)
        outside = self.root.parent / "outside"
        outside.write_text("outside", encoding="utf-8")
        linked = self.root / "linked"
        os.symlink(self.root.parent, linked)
        tx = Transaction.begin(self.root)

        for path in (fifo, outside, linked / "outside", self.root / ".bootstrap" / "transactions"):
            with self.subTest(path=path):
                with self.assertRaises(ApplyError):
                    tx.snapshot(path)
        tx.rollback()

    def test_data_root_must_be_a_real_directory(self) -> None:
        file_root = self.root.parent / "file"
        file_root.write_text("x", encoding="utf-8")
        linked_root = self.root.parent / "linked-root"
        os.symlink(self.root, linked_root)

        for root in (file_root, linked_root):
            with self.subTest(root=root):
                with self.assertRaises(ApplyError):
                    Transaction.begin(root)

    def test_snapshot_duplicate_and_child_coverage_are_noops_but_parent_after_child_fails(self) -> None:
        parent = self.root / "parent"
        parent.mkdir()
        child = parent / "child"
        child.write_text("before", encoding="utf-8")
        tx = Transaction.begin(self.root)

        tx.snapshot(parent)
        tx.snapshot(parent)
        tx.snapshot(child)
        _, journal = self.journal()
        self.assertEqual(len(journal["entries"]), 1)
        tx.rollback()

        tx = Transaction.begin(self.root)
        tx.snapshot(child)
        with self.assertRaises(ApplyError):
            tx.snapshot(parent)
        tx.rollback()

    def test_second_writer_is_rejected_until_the_first_finishes(self) -> None:
        tx = Transaction.begin(self.root)
        with self.assertRaises(ApplyError):
            Transaction.begin(self.root)
        with self.assertRaises(ApplyError):
            Transaction.recover_if_needed(self.root)
        tx.rollback()
        Transaction.begin(self.root).rollback()

    def test_symlinked_lock_is_rejected_without_touching_its_target(self) -> None:
        store = self.make_private_store(self.root)
        outside = self.root.parent / "outside-lock"
        outside.write_text("outside-lock-content", encoding="utf-8")
        outside.chmod(0o644)
        os.symlink(outside, store / ".lock")
        outside_identity = (outside.stat().st_dev, outside.stat().st_ino)
        flocked_external: list[int] = []
        original_flock = transaction_module.fcntl.flock

        def record_flock(descriptor: int, operation: int) -> None:
            info = os.fstat(descriptor)
            if (info.st_dev, info.st_ino) == outside_identity:
                flocked_external.append(operation)
            original_flock(descriptor, operation)

        with mock.patch.object(transaction_module.fcntl, "flock", side_effect=record_flock):
            with self.assertRaises(ApplyError):
                Transaction.begin(self.root)

        self.assertEqual(flocked_external, [])
        self.assertEqual(outside.read_text(encoding="utf-8"), "outside-lock-content")
        self.assertEqual(stat.S_IMODE(outside.lstat().st_mode), 0o644)
        self.assertTrue((store / ".lock").is_symlink())

    def test_persistent_lock_inode_is_private_and_regular(self) -> None:
        store = self.make_private_store(self.root)
        lock = store / ".lock"
        lock.write_text("", encoding="utf-8")
        lock.chmod(0o666)

        tx = Transaction.begin(self.root)

        info = lock.lstat()
        self.assertTrue(stat.S_ISREG(info.st_mode))
        self.assertEqual(stat.S_IMODE(info.st_mode), 0o600)
        tx.rollback()

    def test_hardlinked_lock_is_rejected_without_touching_the_external_inode(self) -> None:
        store = self.make_private_store(self.root)
        outside = self.root.parent / "outside-lock-hardlink"
        outside.write_text("outside-lock-content", encoding="utf-8")
        outside.chmod(0o644)
        os.link(outside, store / ".lock")
        outside_identity = (outside.stat().st_dev, outside.stat().st_ino)
        flocked_external: list[int] = []
        original_flock = transaction_module.fcntl.flock

        def record_flock(descriptor: int, operation: int) -> None:
            info = os.fstat(descriptor)
            if (info.st_dev, info.st_ino) == outside_identity:
                flocked_external.append(operation)
            original_flock(descriptor, operation)

        with mock.patch.object(transaction_module.fcntl, "flock", side_effect=record_flock):
            with self.assertRaises(ApplyError):
                Transaction.begin(self.root)

        self.assertEqual(flocked_external, [])
        self.assertEqual(outside.read_text(encoding="utf-8"), "outside-lock-content")
        self.assertEqual(stat.S_IMODE(outside.lstat().st_mode), 0o644)

    def test_begin_requires_explicit_recovery_of_durable_journal(self) -> None:
        path = self.root / "file"
        path.write_text("before", encoding="utf-8")
        tx = Transaction.begin(self.root)
        tx.snapshot(path)
        path.write_text("after", encoding="utf-8")
        self.crash(tx)

        with self.assertRaises(ApplyError):
            Transaction.begin(self.root)
        Transaction.recover_if_needed(self.root)
        self.assertEqual(path.read_text(encoding="utf-8"), "before")

    def test_recovery_rejects_non_private_transaction_directory_hierarchy(self) -> None:
        for name in ("store", "journal", "backup", "nested-backup"):
            with self.subTest(directory=name), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary) / "data"
                root.mkdir()
                hierarchy, journal_path = self.private_recovery_hierarchy(root)
                hierarchy[name].chmod(0o750)

                with self.assertRaises(ApplyError) as captured:
                    Transaction.recover_if_needed(root)

                self.assertNotIn("trust-boundary-secret", str(captured.exception))
                self.assertNotIn(str(root), str(captured.exception))
                self.assertTrue(journal_path.exists())

    def test_recovery_rejects_transaction_directory_hierarchy_owned_by_another_euid(self) -> None:
        different_owner = os.geteuid() + 1
        for name in ("bootstrap", "store", "journal", "backup", "nested-backup"):
            with self.subTest(directory=name), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary) / "data"
                root.mkdir()
                hierarchy, journal_path = self.private_recovery_hierarchy(root)

                with self.reported_owner(hierarchy[name], different_owner):
                    with self.assertRaises(ApplyError) as captured:
                        Transaction.recover_if_needed(root)

                self.assertNotIn("trust-boundary-secret", str(captured.exception))
                self.assertNotIn(str(root), str(captured.exception))
                self.assertTrue(journal_path.exists())

    def test_recovery_rejects_group_or_other_writable_bootstrap_parent(self) -> None:
        for mode in (0o770, 0o707):
            with self.subTest(mode=oct(mode)), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary) / "data"
                root.mkdir()
                hierarchy, journal_path = self.private_recovery_hierarchy(root)
                hierarchy["bootstrap"].chmod(mode)

                with self.assertRaises(ApplyError) as captured:
                    Transaction.recover_if_needed(root)

                self.assertNotIn("trust-boundary-secret", str(captured.exception))
                self.assertNotIn(str(root), str(captured.exception))
                self.assertTrue(journal_path.exists())

    def test_recovery_accepts_private_transaction_directory_hierarchy(self) -> None:
        hierarchy, journal_path = self.private_recovery_hierarchy(self.root, bootstrap_mode=0o755)

        Transaction.recover_if_needed(self.root)

        bootstrap_info = hierarchy["bootstrap"].lstat()
        self.assertEqual(bootstrap_info.st_uid, os.geteuid())
        self.assertEqual(stat.S_IMODE(bootstrap_info.st_mode), 0o755)
        info = hierarchy["store"].lstat()
        self.assertEqual(info.st_uid, os.geteuid())
        self.assertEqual(stat.S_IMODE(info.st_mode), 0o700)
        for name in ("journal", "backup", "nested-backup"):
            path = hierarchy[name]
            self.assertFalse(path.exists())
        self.assertFalse(journal_path.exists())

    def test_recovery_rejects_invalid_directory_metadata_without_disclosing_it(self) -> None:
        for mutation in ("traversal", "missing-directory"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary) / "data"
                root.mkdir()
                _, journal_path = self.private_recovery_hierarchy(root)
                journal = json.loads(journal_path.read_text(encoding="utf-8"))
                directories = journal["entries"][0]["directories"]
                if mutation == "traversal":
                    directories.append(
                        {
                            "path": "../trust-boundary-secret",
                            "mode": 0o700,
                            "uid": os.geteuid(),
                            "gid": os.getegid(),
                        }
                    )
                else:
                    directories.pop()
                journal_path.write_text(json.dumps(journal), encoding="utf-8")

                with self.assertRaises(ApplyError) as captured:
                    Transaction.recover_if_needed(root)

                self.assertNotIn("trust-boundary-secret", str(captured.exception))
                self.assertNotIn(str(root), str(captured.exception))
                self.assertTrue(journal_path.exists())

    def test_initial_journal_failure_and_empty_directory_recovery_are_safe(self) -> None:
        with mock.patch.object(transaction_module, "_atomic_write_json", side_effect=OSError()):
            with self.assertRaises(ApplyError):
                Transaction.begin(self.root)
        store = self.root / ".bootstrap" / "transactions"
        self.assertEqual([path for path in store.iterdir() if path.name != ".lock"], [])

        empty = store / "00000000-0000-4000-8000-000000000000"
        empty.mkdir(mode=0o700)
        Transaction.recover_if_needed(self.root)
        self.assertFalse(empty.exists())

        nonempty = store / "00000000-0000-4000-8000-000000000001"
        nonempty.mkdir(mode=0o700)
        (nonempty / "unexpected").write_text("unsafe", encoding="utf-8")
        with self.assertRaises(ApplyError):
            Transaction.recover_if_needed(self.root)
        self.assertTrue(nonempty.exists())

    def test_initial_journal_temporary_is_rejected_and_retained(self) -> None:
        def fail_with_temporary(path: Path, _payload: dict[str, object]) -> None:
            (path.parent / ".journal-interrupted").write_text("partial", encoding="utf-8")
            raise OSError

        with mock.patch.object(transaction_module, "_atomic_write_json", side_effect=fail_with_temporary):
            with self.assertRaises(ApplyError):
                Transaction.begin(self.root)
        store = self.root / ".bootstrap" / "transactions"
        transactions = [path for path in store.iterdir() if path.name != ".lock"]
        self.assertEqual(len(transactions), 1)
        interrupted = transactions[0]

        with self.assertRaises(ApplyError):
            Transaction.recover_if_needed(self.root)
        self.assertTrue(interrupted.exists())
        self.assertTrue((interrupted / ".journal-interrupted").exists())

    def test_preparing_ready_and_committed_recovery_are_distinct(self) -> None:
        path = self.root / "file"
        path.write_text("before", encoding="utf-8")

        tx = Transaction.begin(self.root)
        with mock.patch.object(transaction_module, "_failpoint", side_effect=lambda name: (_ for _ in ()).throw(OSError()) if name == "backup-published" else None):
            with self.assertRaises(ApplyError):
                tx.snapshot(path)
        self.crash(tx)
        Transaction.recover_if_needed(self.root)
        self.assertEqual(path.read_text(encoding="utf-8"), "before")

        tx = Transaction.begin(self.root)
        tx.snapshot(path)
        path.write_text("changed", encoding="utf-8")
        self.crash(tx)
        Transaction.recover_if_needed(self.root)
        self.assertEqual(path.read_text(encoding="utf-8"), "before")

        tx = Transaction.begin(self.root)
        tx.snapshot(path)
        path.write_text("committed", encoding="utf-8")
        with mock.patch.object(transaction_module, "_failpoint", side_effect=lambda name: (_ for _ in ()).throw(OSError()) if name == "cleanup-step" else None):
            with self.assertRaises(ApplyError):
                tx.commit()
        self.crash(tx)
        Transaction.recover_if_needed(self.root)
        self.assertEqual(path.read_text(encoding="utf-8"), "committed")

    def test_terminal_cleanup_recovers_after_every_durable_removal_step(self) -> None:
        for point in ("cleanup-backup", "cleanup-journal", "cleanup-directory"):
            with self.subTest(point=point), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary) / "data"
                root.mkdir()
                path = root / "file"
                path.write_text("before", encoding="utf-8")
                tx = Transaction.begin(root)
                tx.snapshot(path)
                path.write_text("committed", encoding="utf-8")

                with mock.patch.object(
                    transaction_module,
                    "_failpoint",
                    side_effect=lambda name, point=point: (_ for _ in ()).throw(OSError())
                    if name == point
                    else None,
                ):
                    with self.assertRaises(ApplyError):
                        tx.commit()

                Transaction.recover_if_needed(root)
                self.assertEqual(path.read_text(encoding="utf-8"), "committed")
                self.assertEqual(list((root / ".bootstrap" / "transactions").glob("*/journal.json")), [])

    def test_terminal_cleanup_recovers_after_temporary_object_removal(self) -> None:
        path = self.root / "file"
        path.write_text("before", encoding="utf-8")
        tx = Transaction.begin(self.root)
        tx.snapshot(path)
        path.write_text("committed", encoding="utf-8")
        with mock.patch.object(
            transaction_module,
            "_failpoint",
            side_effect=lambda name: (_ for _ in ()).throw(OSError()) if name == "status-update" else None,
        ):
            with self.assertRaises(ApplyError):
                tx.commit()
        journal_path, _ = self.journal()
        (journal_path.parent / ".journal-leftover").write_text("temporary", encoding="utf-8")

        with mock.patch.object(
            transaction_module,
            "_failpoint",
            side_effect=lambda name: (_ for _ in ()).throw(OSError()) if name == "cleanup-temp" else None,
        ):
            with self.assertRaises(ApplyError):
                Transaction.recover_if_needed(self.root)
        self.assertTrue(journal_path.exists())

        Transaction.recover_if_needed(self.root)
        self.assertEqual(path.read_text(encoding="utf-8"), "committed")

    def test_journal_rejects_illegal_status_and_entry_state_combinations(self) -> None:
        cases = (
            ("active", ("restored", "ready")),
            ("rolling_back", ("restored", "ready")),
            ("committed", ("ready", "preparing")),
            ("committed", ("ready", "restored")),
            ("rolled_back", ("restored", "ready")),
        )
        for status, states in cases:
            with self.subTest(status=status, states=states), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary) / "data"
                root.mkdir()
                first = root / "first"
                second = root / "second"
                first.write_text("first-before", encoding="utf-8")
                second.write_text("second-before", encoding="utf-8")
                tx = Transaction.begin(root)
                tx.snapshot(first)
                tx.snapshot(second)
                first.write_text("first-after", encoding="utf-8")
                second.write_text("second-after", encoding="utf-8")
                journal_path = next((root / ".bootstrap" / "transactions").glob("*/journal.json"))
                journal = json.loads(journal_path.read_text(encoding="utf-8"))
                journal["status"] = status
                for entry, state in zip(journal["entries"], states, strict=True):
                    entry["state"] = state
                journal_path.write_text(json.dumps(journal), encoding="utf-8")
                self.crash(tx)

                with self.assertRaises(ApplyError):
                    Transaction.recover_if_needed(root)
                self.assertEqual(first.read_text(encoding="utf-8"), "first-after")
                self.assertEqual(second.read_text(encoding="utf-8"), "second-after")
                self.assertTrue(journal_path.exists())

    def test_journal_rejects_the_removed_inode_based_move_kind(self) -> None:
        path = self.root / "file"
        path.write_text("before", encoding="utf-8")
        tx = Transaction.begin(self.root)
        tx.snapshot(path)
        path.write_text("after", encoding="utf-8")
        journal_path, journal = self.journal()
        journal["entries"][0]["kind"] = "move"
        journal_path.write_text(json.dumps(journal), encoding="utf-8")
        self.crash(tx)

        with self.assertRaises(ApplyError):
            Transaction.recover_if_needed(self.root)

        self.assertEqual(path.read_text(encoding="utf-8"), "after")
        self.assertTrue(journal_path.exists())

    def test_rolling_back_journal_accepts_only_a_restored_reverse_suffix(self) -> None:
        first = self.root / "first"
        second = self.root / "second"
        first.write_text("first-before", encoding="utf-8")
        second.write_text("second-before", encoding="utf-8")
        tx = Transaction.begin(self.root)
        tx.snapshot(first)
        tx.snapshot(second)
        first.write_text("first-after", encoding="utf-8")
        second.write_text("second-before", encoding="utf-8")
        journal_path, journal = self.journal()
        journal["status"] = "rolling_back"
        journal["entries"][1]["state"] = "restored"
        journal_path.write_text(json.dumps(journal), encoding="utf-8")
        self.crash(tx)

        Transaction.recover_if_needed(self.root)

        self.assertEqual(first.read_text(encoding="utf-8"), "first-before")
        self.assertEqual(second.read_text(encoding="utf-8"), "second-before")
        self.assertEqual(self.journal_paths(), [])

    def test_terminal_rolled_back_allows_only_restored_entries_then_trailing_preparing(self) -> None:
        source = self.root / "source"
        target = self.root / "target"
        source.write_text("source-before", encoding="utf-8")
        tx = Transaction.begin(self.root)
        tx.snapshot(source)
        tx.snapshot(target)
        os.replace(source, target)
        journal_path, journal = self.journal()
        journal["entries"].append(
            {
                "kind": "snapshot",
                "path": "trailing",
                "state": "preparing",
                "original": "absent",
                "backup": "backup-000002",
            }
        )
        journal_path.write_text(json.dumps(journal), encoding="utf-8")
        self.crash(tx)

        def fail_after_rolled_back(name: str) -> None:
            if name != "journal-write":
                return
            _, journal = self.journal()
            if journal["status"] == "rolled_back":
                raise OSError

        with mock.patch.object(transaction_module, "_failpoint", side_effect=fail_after_rolled_back):
            with self.assertRaises(RollbackError):
                Transaction.recover_if_needed(self.root)

        journal_path, journal = self.journal()
        self.assertEqual(journal["status"], "rolled_back")
        self.assertEqual(
            [entry["state"] for entry in journal["entries"]],
            ["restored", "restored", "preparing"],
        )
        Transaction.recover_if_needed(self.root)
        self.assertEqual(source.read_text(encoding="utf-8"), "source-before")
        self.assertFalse(os.path.lexists(target))
        self.assertFalse(journal_path.exists())

        tx = Transaction.begin(self.root)
        tx.snapshot(source)
        source.write_text("tampered", encoding="utf-8")
        journal_path, journal = self.journal()
        journal["entries"][0]["state"] = "restored"
        journal_path.write_text(json.dumps(journal), encoding="utf-8")
        self.crash(tx)
        with self.assertRaises(ApplyError):
            Transaction.recover_if_needed(self.root)
        self.assertEqual(source.read_text(encoding="utf-8"), "tampered")

    def test_malformed_or_traversing_journal_is_rejected_before_targets_are_touched(self) -> None:
        store = self.make_private_store(self.root)
        (store / ".lock").touch()
        journal_dir = store / "00000000-0000-4000-8000-000000000000"
        journal_dir.mkdir(mode=0o700)
        journal = journal_dir / "journal.json"
        journal.write_text(
            json.dumps({"version": 2, "status": "active", "entries": [{"kind": "snapshot", "path": "../escape", "state": "ready", "original": "absent", "backup": "backup-000000"}]}),
            encoding="utf-8",
        )
        victim = self.root.parent / "escape"
        victim.write_text("safe", encoding="utf-8")

        with self.assertRaises(ApplyError):
            Transaction.recover_if_needed(self.root)
        self.assertEqual(victim.read_text(encoding="utf-8"), "safe")

    def test_unexpected_journal_object_is_rejected_before_ready_restore(self) -> None:
        path = self.root / "file"
        path.write_text("before", encoding="utf-8")
        tx = Transaction.begin(self.root)
        tx.snapshot(path)
        path.write_text("after", encoding="utf-8")
        journal_path, _ = self.journal()
        (journal_path.parent / "backup-999999").write_text("unexpected", encoding="utf-8")
        self.crash(tx)

        with self.assertRaises(ApplyError):
            Transaction.recover_if_needed(self.root)
        self.assertEqual(path.read_text(encoding="utf-8"), "after")

    def test_faults_after_each_write_ahead_step_recover_without_data_loss(self) -> None:
        path = self.root / "file"
        for point in ("journal-write", "backup-published", "entry-ready"):
            with self.subTest(point=point):
                path.write_text("before", encoding="utf-8")
                tx = Transaction.begin(self.root)
                with mock.patch.object(transaction_module, "_failpoint", side_effect=lambda name, point=point: (_ for _ in ()).throw(OSError()) if name == point else None):
                    with self.assertRaises(ApplyError):
                        tx.snapshot(path)
                self.crash(tx)
                Transaction.recover_if_needed(self.root)
                self.assertEqual(path.read_text(encoding="utf-8"), "before")

        tx = Transaction.begin(self.root)
        tx.snapshot(path)
        path.write_text("mutated", encoding="utf-8")
        self.crash(tx)
        Transaction.recover_if_needed(self.root)
        self.assertEqual(path.read_text(encoding="utf-8"), "before")

    def test_interrupted_restore_is_idempotently_recovered(self) -> None:
        path = self.root / "file"
        path.write_text("before", encoding="utf-8")
        tx = Transaction.begin(self.root)
        tx.snapshot(path)
        path.write_text("after", encoding="utf-8")
        self.crash(tx)

        with mock.patch.object(transaction_module, "_failpoint", side_effect=lambda name: (_ for _ in ()).throw(OSError()) if name == "restore" else None):
            with self.assertRaises(RollbackError):
                Transaction.recover_if_needed(self.root)
        self.assertTrue(self.journal_paths())
        Transaction.recover_if_needed(self.root)
        self.assertEqual(path.read_text(encoding="utf-8"), "before")

    def test_failure_to_enter_rolling_back_is_reported_as_rollback_error(self) -> None:
        path = self.root / "file"
        path.write_text("before", encoding="utf-8")
        tx = Transaction.begin(self.root)
        tx.snapshot(path)
        path.write_text("after", encoding="utf-8")
        self.crash(tx)
        original_write = transaction_module._atomic_write_json

        def fail_rolling_back(journal_path: Path, payload: dict[str, object]) -> None:
            if payload["status"] == "rolling_back":
                raise OSError
            original_write(journal_path, payload)

        with mock.patch.object(transaction_module, "_atomic_write_json", side_effect=fail_rolling_back):
            with self.assertRaises(RollbackError):
                Transaction.recover_if_needed(self.root)

        self.assertEqual(path.read_text(encoding="utf-8"), "after")
        self.assertTrue(self.journal_paths())

    def test_restore_revalidates_ancestors_after_journal_validation(self) -> None:
        managed = self.root / "managed"
        managed.mkdir()
        path = managed / "file"
        path.write_text("before", encoding="utf-8")
        outside = self.root.parent / "outside"
        outside.mkdir()
        sentinel = outside / "file"
        sentinel.write_text("outside-sentinel", encoding="utf-8")
        tx = Transaction.begin(self.root)
        tx.snapshot(path)
        path.write_text("after", encoding="utf-8")
        self.crash(tx)
        swapped = False

        def swap_ancestor(name: str) -> None:
            nonlocal swapped
            if name != "before-restore" or swapped:
                return
            swapped = True
            os.replace(managed, self.root / "parked-managed")
            os.symlink(outside, managed)

        with mock.patch.object(transaction_module, "_failpoint", side_effect=swap_ancestor):
            with self.assertRaises(RollbackError):
                Transaction.recover_if_needed(self.root)

        self.assertEqual(sentinel.read_text(encoding="utf-8"), "outside-sentinel")
        self.assertTrue(self.journal_paths())

    def test_restore_mutations_remain_bound_when_an_ancestor_is_swapped(self) -> None:
        managed = self.root / "managed"
        managed.mkdir()
        path = managed / "file"
        path.write_text("before", encoding="utf-8")
        outside = self.root.parent / "outside-race"
        outside.mkdir()
        sentinel = outside / "file"
        sentinel.write_text("outside-sentinel", encoding="utf-8")
        tx = Transaction.begin(self.root)
        tx.snapshot(path)
        path.write_text("after", encoding="utf-8")
        self.crash(tx)
        original_replace = transaction_module.os.replace
        swapped = False

        def swap_before_managed_replace(source: object, target: object, *args: object, **kwargs: object) -> None:
            nonlocal swapped
            if not swapped and Path(os.fsdecode(source)).name == "file" and Path(os.fsdecode(target)).name.startswith(".file.bootstrap-"):
                swapped = True
                original_replace(managed, self.root / "parked-managed")
                os.symlink(outside, managed)
            original_replace(source, target, *args, **kwargs)

        with mock.patch.object(transaction_module.os, "replace", side_effect=swap_before_managed_replace):
            with self.assertRaises(RollbackError):
                Transaction.recover_if_needed(self.root)

        self.assertTrue(swapped)
        self.assertEqual(sentinel.read_text(encoding="utf-8"), "outside-sentinel")
        self.assertTrue(self.journal_paths())

    def test_rollback_failure_retains_journal_and_redacts_runtime_content(self) -> None:
        path = self.root / "file"
        secret = "do-not-expose-this-runtime-content"
        path.write_text(secret, encoding="utf-8")
        tx = Transaction.begin(self.root)
        tx.snapshot(path)
        path.unlink()
        os.mkfifo(path)

        with self.assertRaises(RollbackError) as captured:
            tx.rollback()
        self.assertNotIn(secret, str(captured.exception))
        self.assertTrue(self.journal_paths())
        path.unlink()
        Transaction.recover_if_needed(self.root)
        self.assertEqual(path.read_text(encoding="utf-8"), secret)

    def test_commit_marks_status_before_cleanup_and_repeated_calls_are_deterministic(self) -> None:
        path = self.root / "file"
        path.write_text("before", encoding="utf-8")
        tx = Transaction.begin(self.root)
        tx.snapshot(path)
        path.write_text("after", encoding="utf-8")

        with mock.patch.object(transaction_module, "_failpoint", side_effect=lambda name: (_ for _ in ()).throw(OSError()) if name == "status-update" else None):
            with self.assertRaises(ApplyError):
                tx.commit()
        self.crash(tx)
        Transaction.recover_if_needed(self.root)
        self.assertEqual(path.read_text(encoding="utf-8"), "after")
        self.assertEqual(self.journal_paths(), [])

        tx = Transaction.begin(self.root)
        tx.commit()
        tx.commit()
        with self.assertRaises(ApplyError):
            tx.rollback()

    def test_successful_operations_fsync_journal_and_managed_parent(self) -> None:
        path = self.root / "file"
        path.write_text("before", encoding="utf-8")
        calls: list[Path] = []
        original = transaction_module._fsync_directory

        def record(directory: Path) -> None:
            calls.append(directory)
            original(directory)

        with mock.patch.object(transaction_module, "_fsync_directory", side_effect=record):
            tx = Transaction.begin(self.root)
            tx.snapshot(path)
            path.write_text("after", encoding="utf-8")
            tx.rollback()

        self.assertIn(path.parent, calls)
        self.assertTrue(any("transactions" in directory.parts for directory in calls))


if __name__ == "__main__":
    unittest.main()
