"""Safety tests for Hermes named-volume ownership convergence."""

from __future__ import annotations

import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

from hermes_storage_ownership import converge_ownership


def _alternate_id(current: int) -> int:
    return 10000 if current != 10000 else 10001


def _with_ownership(info: os.stat_result, uid: int, gid: int) -> SimpleNamespace:
    return SimpleNamespace(
        st_dev=info.st_dev,
        st_ino=info.st_ino,
        st_mode=info.st_mode,
        st_uid=uid,
        st_gid=gid,
        st_mtime_ns=info.st_mtime_ns,
    )


class HermesStorageOwnershipTests(unittest.TestCase):
    def test_refreshes_nested_directory_metadata_after_recursive_traversal(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            nested = root / "nested"
            nested.mkdir(parents=True)
            (nested / "already-owned").write_text("state\n", encoding="utf-8")
            target_uid = os.getuid()
            target_gid = os.getgid()
            stale_uid = _alternate_id(target_uid)
            nested_inode = nested.stat().st_ino
            real_fstat = os.fstat
            real_scandir = os.scandir
            nested_scans = 0
            ownership_changes: list[int] = []

            def report_stale_nested_owner(fd: int) -> os.stat_result | SimpleNamespace:
                info = real_fstat(fd)
                if info.st_ino == nested_inode:
                    return _with_ownership(info, stale_uid, target_gid)
                return info

            def add_setid_during_recursive_traversal(fd: int):
                nonlocal nested_scans
                info = real_fstat(fd)
                if info.st_ino == nested_inode:
                    nested_scans += 1
                    if nested_scans == 2:
                        os.fchmod(fd, 0o2750)
                return real_scandir(fd)

            with (
                mock.patch(
                    "hermes_storage_ownership.os.fstat",
                    side_effect=report_stale_nested_owner,
                ),
                mock.patch(
                    "hermes_storage_ownership.os.scandir",
                    side_effect=add_setid_during_recursive_traversal,
                ),
                mock.patch(
                    "hermes_storage_ownership.os.fchown",
                    side_effect=lambda fd, _uid, _gid: ownership_changes.append(
                        real_fstat(fd).st_ino
                    ),
                ),
                self.assertRaises(RuntimeError),
            ):
                converge_ownership(root, target_uid, target_gid)

            self.assertNotIn(nested_inode, ownership_changes)
            self.assertEqual(stat.S_IMODE(nested.stat().st_mode), 0o2750)

    def test_refreshes_root_metadata_after_recursive_traversal(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            root.mkdir()
            (root / "already-owned").write_text("state\n", encoding="utf-8")
            target_uid = os.getuid()
            target_gid = os.getgid()
            stale_uid = _alternate_id(target_uid)
            root_inode = root.stat().st_ino
            real_fstat = os.fstat
            real_scandir = os.scandir
            root_scans = 0
            ownership_changes: list[int] = []

            def report_stale_root_owner(fd: int) -> os.stat_result | SimpleNamespace:
                info = real_fstat(fd)
                if info.st_ino == root_inode:
                    return _with_ownership(info, stale_uid, target_gid)
                return info

            def add_setid_during_recursive_traversal(fd: int):
                nonlocal root_scans
                info = real_fstat(fd)
                if info.st_ino == root_inode:
                    root_scans += 1
                    if root_scans == 2:
                        os.fchmod(fd, 0o2750)
                return real_scandir(fd)

            with (
                mock.patch(
                    "hermes_storage_ownership.os.fstat",
                    side_effect=report_stale_root_owner,
                ),
                mock.patch(
                    "hermes_storage_ownership.os.scandir",
                    side_effect=add_setid_during_recursive_traversal,
                ),
                mock.patch(
                    "hermes_storage_ownership.os.fchown",
                    side_effect=lambda fd, _uid, _gid: ownership_changes.append(
                        real_fstat(fd).st_ino
                    ),
                ),
                self.assertRaises(RuntimeError),
            ):
                converge_ownership(root, target_uid, target_gid)

            self.assertNotIn(root_inode, ownership_changes)
            self.assertEqual(stat.S_IMODE(root.stat().st_mode), 0o2750)

    @unittest.skipUnless(
        sys.platform.startswith("linux") and os.geteuid() == 0,
        "requires Linux root ownership semantics",
    )
    def test_rejects_setid_transition_before_any_owner_changes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            root.mkdir()
            for name in ("candidate-a", "candidate-b"):
                (root / name).write_bytes(name.encode("ascii") + b"\x00data")
            with os.scandir(root) as entries:
                ordinary, setid = (root / entry.name for entry in entries)

            ordinary.chmod(0o640)
            setid.chmod(0o6750)

            paths = (root, ordinary, setid)
            before = {
                path.name: (
                    path.stat().st_uid,
                    path.stat().st_gid,
                    stat.S_IMODE(path.stat().st_mode),
                    path.stat().st_mtime_ns,
                )
                for path in paths
            }
            contents = {path.name: path.read_bytes() for path in (ordinary, setid)}

            with self.assertRaises(RuntimeError):
                converge_ownership(root, 10000, 10000)

            after = {
                path.name: (
                    path.stat().st_uid,
                    path.stat().st_gid,
                    stat.S_IMODE(path.stat().st_mode),
                    path.stat().st_mtime_ns,
                )
                for path in paths
            }
            self.assertEqual(after, before)
            self.assertEqual(
                {path.name: path.read_bytes() for path in (ordinary, setid)},
                contents,
            )

    def test_changes_only_regular_files_and_directories(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            nested = root / "nested"
            nested.mkdir(parents=True)
            regular = nested / "state.db"
            regular.write_bytes(b"state\x00bytes")
            symlink = root / "state-link"
            symlink.symlink_to("nested/state.db")
            fifo = root / "events.fifo"
            if hasattr(os, "mkfifo"):
                os.mkfifo(fifo)

            target_uid = _alternate_id(os.getuid())
            target_gid = _alternate_id(os.getgid())
            changed_inodes: set[int] = set()
            real_fstat = os.fstat

            def record_fchown(fd: int, uid: int, gid: int) -> None:
                self.assertEqual((uid, gid), (target_uid, target_gid))
                changed_inodes.add(real_fstat(fd).st_ino)

            def report_changed_ownership(fd: int) -> os.stat_result | SimpleNamespace:
                info = real_fstat(fd)
                if info.st_ino in changed_inodes:
                    return _with_ownership(info, target_uid, target_gid)
                return info

            with (
                mock.patch(
                    "hermes_storage_ownership.os.fchown",
                    side_effect=record_fchown,
                ),
                mock.patch(
                    "hermes_storage_ownership.os.fstat",
                    side_effect=report_changed_ownership,
                ),
            ):
                converge_ownership(root, target_uid, target_gid)

            self.assertEqual(
                set(changed_inodes),
                {root.stat().st_ino, nested.stat().st_ino, regular.stat().st_ino},
            )
            self.assertNotIn(symlink.lstat().st_ino, changed_inodes)
            if fifo.exists():
                self.assertNotIn(fifo.lstat().st_ino, changed_inodes)

    def test_preserves_bytes_names_modes_and_mtimes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            nested = root / "nested directory"
            nested.mkdir(parents=True)
            regular = nested / "state ?#%.db"
            regular.write_bytes(b"persistent\x00payload\n")
            regular.chmod(0o751)
            nested.chmod(0o750)
            root.chmod(0o755)
            os.utime(regular, ns=(1_700_000_000_111_111_111, 1_700_000_000_222_222_222))
            os.utime(nested, ns=(1_700_000_001_111_111_111, 1_700_000_001_222_222_222))
            os.utime(root, ns=(1_700_000_002_111_111_111, 1_700_000_002_222_222_222))

            before = {
                path.relative_to(root).as_posix(): (
                    stat.S_IMODE(path.stat().st_mode),
                    path.stat().st_mtime_ns,
                )
                for path in (root, nested, regular)
            }
            original_bytes = regular.read_bytes()

            converge_ownership(root, os.getuid(), os.getgid())

            after = {
                path.relative_to(root).as_posix(): (
                    stat.S_IMODE(path.stat().st_mode),
                    path.stat().st_mtime_ns,
                )
                for path in (root, nested, regular)
            }
            self.assertEqual(after, before)
            self.assertEqual(regular.read_bytes(), original_bytes)
            self.assertEqual(
                sorted(path.relative_to(root).as_posix() for path in root.rglob("*")),
                ["nested directory", "nested directory/state ?#%.db"],
            )

    def test_skips_a_directory_on_another_filesystem(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            foreign = root / "foreign"
            foreign.mkdir(parents=True)
            foreign_file = foreign / "keep-owner"
            foreign_file.write_text("untouched\n", encoding="utf-8")
            root_device = root.stat().st_dev
            real_stat = os.stat
            target_uid = _alternate_id(os.getuid())
            target_gid = _alternate_id(os.getgid())
            changed_inodes: set[int] = set()
            real_fstat = os.fstat

            def report_foreign_device(
                path: object, *args: object, **kwargs: object
            ) -> os.stat_result:
                result = real_stat(path, *args, **kwargs)
                if path == "foreign" and kwargs.get("dir_fd") is not None:
                    fields = list(result)
                    fields[2] = root_device + 1
                    return os.stat_result(fields)
                return result

            def record_fchown(fd: int, uid: int, gid: int) -> None:
                self.assertEqual((uid, gid), (target_uid, target_gid))
                changed_inodes.add(real_fstat(fd).st_ino)

            def report_changed_ownership(fd: int) -> os.stat_result | SimpleNamespace:
                info = real_fstat(fd)
                if info.st_ino in changed_inodes:
                    return _with_ownership(info, target_uid, target_gid)
                return info

            with (
                mock.patch(
                    "hermes_storage_ownership.os.stat",
                    side_effect=report_foreign_device,
                ),
                mock.patch(
                    "hermes_storage_ownership.os.fchown", side_effect=record_fchown
                ),
                mock.patch(
                    "hermes_storage_ownership.os.fstat",
                    side_effect=report_changed_ownership,
                ),
            ):
                converge_ownership(root, target_uid, target_gid)

            self.assertEqual(changed_inodes, {root.stat().st_ino})
            self.assertNotIn(foreign.stat().st_ino, changed_inodes)
            self.assertNotIn(foreign_file.stat().st_ino, changed_inodes)

    def test_refuses_a_symlink_as_the_target_root(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            actual = parent / "actual"
            actual.mkdir()
            target = parent / "target"
            target.symlink_to(actual, target_is_directory=True)

            with self.assertRaises(OSError):
                converge_ownership(target, os.getuid(), os.getgid())

    def test_fails_closed_when_an_entry_is_replaced_with_a_symlink(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            root.mkdir()
            victim = root / "victim"
            victim.write_text("replace me\n", encoding="utf-8")
            outside = Path(temporary) / "outside"
            outside.write_text("must stay untouched\n", encoding="utf-8")
            outside_before = outside.stat()
            real_open = os.open
            replaced = False

            def replace_before_open(
                path: object,
                flags: int,
                mode: int = 0o777,
                *,
                dir_fd: int | None = None,
            ) -> int:
                nonlocal replaced
                if path == "victim" and dir_fd is not None and not replaced:
                    replaced = True
                    victim.unlink()
                    victim.symlink_to(outside)
                return real_open(path, flags, mode, dir_fd=dir_fd)

            with (
                mock.patch(
                    "hermes_storage_ownership.os.open", side_effect=replace_before_open
                ),
                self.assertRaises(OSError),
            ):
                converge_ownership(root, os.getuid(), os.getgid())

            outside_after = outside.stat()
            self.assertTrue(victim.is_symlink())
            self.assertEqual(
                outside.read_text(encoding="utf-8"), "must stay untouched\n"
            )
            self.assertEqual(outside_after.st_uid, outside_before.st_uid)
            self.assertEqual(outside_after.st_gid, outside_before.st_gid)


if __name__ == "__main__":
    unittest.main()
