from __future__ import annotations

import os
import socket
import stat
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


BOOTSTRAP_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BOOTSTRAP_ROOT))

from hermes_bootstrap import filesystem


def _with_device(status: os.stat_result, device: int) -> os.stat_result:
    values = list(status)
    values[2] = device
    return os.stat_result(values)


class PrivateDirectoryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.parent = Path(self.temporary.name).resolve()

    def private_directory(self) -> filesystem.PrivateDirectory:
        return filesystem.create_private_directory(
            self.parent,
            prefix="private-",
        )

    def test_cleanup_removes_a_normal_nested_regular_file_tree(self) -> None:
        private = self.private_directory()
        nested = private.path / "first" / "second"
        nested.mkdir(parents=True)
        (private.path / "root.txt").write_bytes(b"root\n")
        (nested / "nested.txt").write_bytes(b"nested\n")

        self.assertEqual(
            private._state,
            filesystem._PrivateDirectoryState.ACTIVE,
        )
        self.assertTrue(private.cleanup())

        self.assertFalse(private.path.exists())
        self.assertEqual(
            private._state,
            filesystem._PrivateDirectoryState.CLEANED,
        )

    def test_cleanup_refuses_a_symlink_without_following_its_target(self) -> None:
        private = self.private_directory()
        outside = self.parent / "outside"
        outside.write_bytes(b"outside\n")
        link = private.path / "link"
        link.symlink_to(outside)

        self.assertFalse(private.cleanup())

        self.assertTrue(link.is_symlink())
        self.assertEqual(outside.read_bytes(), b"outside\n")
        self.assertEqual(
            private._state,
            filesystem._PrivateDirectoryState.FAILED,
        )

    def test_cleanup_refuses_fifo_and_socket_entries(self) -> None:
        for kind in ("fifo", "socket"):
            with self.subTest(kind=kind):
                private = self.private_directory()
                special = private.path / kind
                listener: socket.socket | None = None
                if kind == "fifo":
                    os.mkfifo(special)
                else:
                    listener = socket.socket(socket.AF_UNIX)
                    listener.bind(str(special))
                try:
                    self.assertFalse(private.cleanup())
                    self.assertTrue(special.exists())
                finally:
                    if listener is not None:
                        listener.close()

    def test_cleanup_refuses_an_entry_from_a_different_device(self) -> None:
        private = self.private_directory()
        child = private.path / "child.txt"
        child.write_bytes(b"child\n")
        real_stat = os.stat

        def different_device(
            path: os.PathLike[str] | str | int,
            *arguments: object,
            **keywords: object,
        ) -> os.stat_result:
            status = real_stat(path, *arguments, **keywords)
            if path == child.name and keywords.get("dir_fd") == private._directory_fd:
                return _with_device(status, status.st_dev + 1)
            return status

        with mock.patch.object(filesystem.os, "stat", side_effect=different_device):
            self.assertFalse(private.cleanup())

        self.assertEqual(child.read_bytes(), b"child\n")

    def test_cleanup_refuses_a_regular_file_with_an_external_hardlink(self) -> None:
        private = self.private_directory()
        child = private.path / "child.txt"
        child.write_bytes(b"child\n")
        external = self.parent / "external.txt"
        os.link(child, external)

        self.assertFalse(private.cleanup())

        self.assertEqual(child.read_bytes(), b"child\n")
        self.assertEqual(external.read_bytes(), b"child\n")

    @unittest.skipUnless(sys.platform.startswith("linux"), "Linux mount IDs required")
    def test_cleanup_refuses_an_entry_from_a_different_mount_on_the_same_device(
        self,
    ) -> None:
        private = self.private_directory()
        child = private.path / "child.txt"
        child.write_bytes(b"child\n")
        root_mount_id = private._mount_id

        def mount_id(descriptor: int) -> int | None:
            status = os.fstat(descriptor)
            if (status.st_dev, status.st_ino) == private.identity:
                return root_mount_id
            return None if root_mount_id is None else root_mount_id + 1

        with mock.patch.object(
            filesystem,
            "_descriptor_mount_id",
            create=True,
            side_effect=mount_id,
        ):
            self.assertFalse(private.cleanup())

        self.assertEqual(child.read_bytes(), b"child\n")

    @unittest.skipUnless(sys.platform.startswith("linux"), "Linux mount IDs required")
    def test_cleanup_fails_closed_for_unavailable_mount_information(self) -> None:
        for result in (None, OSError("malformed mount information")):
            with self.subTest(result=result):
                private = self.private_directory()
                (private.path / "child.txt").write_bytes(b"child\n")
                patch = mock.patch.object(
                    filesystem,
                    "_descriptor_mount_id",
                    create=True,
                    return_value=result,
                )
                if isinstance(result, BaseException):
                    patch = mock.patch.object(
                        filesystem,
                        "_descriptor_mount_id",
                        create=True,
                        side_effect=result,
                    )
                with patch:
                    self.assertFalse(private.cleanup())
                self.assertTrue(private.path.exists())

    def test_cleanup_refuses_a_top_level_identity_mismatch(self) -> None:
        private = self.private_directory()
        retired = private.path.with_name(f"{private.path.name}-retained")
        private.path.rename(retired)
        private.path.mkdir(mode=0o700)
        (private.path / "replacement").write_bytes(b"replacement\n")
        (retired / "captured").write_bytes(b"captured\n")

        self.assertFalse(private.cleanup())

        self.assertEqual((private.path / "replacement").read_bytes(), b"replacement\n")
        self.assertEqual((retired / "captured").read_bytes(), b"captured\n")

    def test_cleanup_refuses_a_child_identity_mismatch(self) -> None:
        private = self.private_directory()
        child = private.path / "child.txt"
        child.write_bytes(b"captured\n")
        retained = private.path / "retained.txt"
        real_open = os.open
        replaced = False

        def replace_before_open(
            path: os.PathLike[str] | str,
            flags: int,
            mode: int = 0o777,
            *,
            dir_fd: int | None = None,
        ) -> int:
            nonlocal replaced
            if (
                not replaced
                and path == child.name
                and dir_fd == private._directory_fd
            ):
                child.rename(retained)
                child.write_bytes(b"replacement\n")
                replaced = True
            return real_open(path, flags, mode, dir_fd=dir_fd)

        with mock.patch.object(filesystem.os, "open", side_effect=replace_before_open):
            self.assertFalse(private.cleanup())

        self.assertEqual(child.read_bytes(), b"replacement\n")
        self.assertEqual(retained.read_bytes(), b"captured\n")

    def test_cleanup_retains_artifacts_after_an_injected_scan_failure(self) -> None:
        private = self.private_directory()
        child = private.path / "child.txt"
        child.write_bytes(b"child\n")
        real_scandir = os.scandir

        def fail_root_scan(path: os.PathLike[str] | str | int):
            if path == private._directory_fd:
                raise OSError("injected scan failure")
            return real_scandir(path)

        with mock.patch.object(filesystem.os, "scandir", side_effect=fail_root_scan):
            self.assertFalse(private.cleanup())

        self.assertEqual(child.read_bytes(), b"child\n")
        self.assertFalse(private.cleanup())

    def test_cleanup_retains_the_entry_after_an_injected_unlink_failure(self) -> None:
        private = self.private_directory()
        child = private.path / "child.txt"
        child.write_bytes(b"child\n")
        real_unlink = os.unlink

        def fail_child_unlink(
            path: os.PathLike[str] | str,
            *,
            dir_fd: int | None = None,
        ) -> None:
            if path == child.name and dir_fd == private._directory_fd:
                raise OSError("injected unlink failure")
            real_unlink(path, dir_fd=dir_fd)

        with mock.patch.object(filesystem.os, "unlink", side_effect=fail_child_unlink):
            self.assertFalse(private.cleanup())

        self.assertEqual(child.read_bytes(), b"child\n")
        self.assertFalse(private.cleanup())

    def test_cleanup_retains_the_root_after_an_injected_rmdir_failure(self) -> None:
        private = self.private_directory()
        real_rmdir = os.rmdir

        def fail_root_rmdir(
            path: os.PathLike[str] | str,
            *,
            dir_fd: int | None = None,
        ) -> None:
            if path == private.path.name and dir_fd == private._parent_fd:
                raise OSError("injected rmdir failure")
            real_rmdir(path, dir_fd=dir_fd)

        with mock.patch.object(filesystem.os, "rmdir", side_effect=fail_root_rmdir):
            self.assertFalse(private.cleanup())

        self.assertTrue(private.path.is_dir())
        self.assertFalse(private.cleanup())

    def test_repeated_cleanup_after_cleaned_returns_true(self) -> None:
        private = self.private_directory()

        self.assertTrue(private.cleanup())
        self.assertTrue(private.cleanup())

    def test_repeated_cleanup_after_failed_returns_false(self) -> None:
        private = self.private_directory()
        os.mkfifo(private.path / "retained")

        self.assertFalse(private.cleanup())
        self.assertFalse(private.cleanup())
        self.assertEqual(
            private._state,
            filesystem._PrivateDirectoryState.FAILED,
        )

    def test_cleanup_after_release_returns_false_without_deleting_published_path(
        self,
    ) -> None:
        private = self.private_directory()
        published = self.parent / "published"
        private.path.rename(published)
        (published / "content").write_bytes(b"published\n")

        private.release()

        self.assertFalse(private.cleanup())
        self.assertEqual((published / "content").read_bytes(), b"published\n")
        self.assertEqual(
            private._state,
            filesystem._PrivateDirectoryState.RELEASED,
        )


if __name__ == "__main__":
    unittest.main()
