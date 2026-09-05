"""Safety tests for Hermes named-volume ownership convergence."""

from __future__ import annotations

import os
import stat
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from hermes_storage_ownership import converge_ownership


class HermesStorageOwnershipTests(unittest.TestCase):
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

            changed_inodes: list[int] = []
            real_fchown = os.fchown

            def record_fchown(fd: int, uid: int, gid: int) -> None:
                changed_inodes.append(os.fstat(fd).st_ino)
                real_fchown(fd, uid, gid)

            with mock.patch(
                "hermes_storage_ownership.os.fchown", side_effect=record_fchown
            ):
                converge_ownership(root, os.getuid(), os.getgid())

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
            real_fchown = os.fchown
            changed_inodes: list[int] = []

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
                changed_inodes.append(os.fstat(fd).st_ino)
                real_fchown(fd, uid, gid)

            with (
                mock.patch(
                    "hermes_storage_ownership.os.stat",
                    side_effect=report_foreign_device,
                ),
                mock.patch(
                    "hermes_storage_ownership.os.fchown", side_effect=record_fchown
                ),
            ):
                converge_ownership(root, os.getuid(), os.getgid())

            self.assertEqual(changed_inodes, [root.stat().st_ino])
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
