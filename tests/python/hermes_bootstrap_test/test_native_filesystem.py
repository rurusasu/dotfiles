"""Native filesystem contracts for publication and descriptor projection."""

from __future__ import annotations

import errno
import os
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

from hermes_bootstrap import profile_snapshot, repositories, transaction


class AtomicRenameTests(unittest.TestCase):
    adapters = (
        repositories._rename_noreplace,
        transaction._rename_noreplace,
        profile_snapshot._rename_noreplace_at,
    )

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()

    def open_parent(self, parent: Path) -> int:
        descriptor = os.open(parent, os.O_RDONLY | os.O_DIRECTORY)
        self.addCleanup(os.close, descriptor)
        return descriptor

    def identity(self, path: Path) -> tuple[int, int]:
        status = path.lstat()
        return status.st_dev, status.st_ino

    def test_directory_publication_preserves_inode_across_parents(self) -> None:
        for index, adapter in enumerate(self.adapters):
            with self.subTest(adapter=adapter.__module__):
                source_parent = self.root / f"source-{index}"
                target_parent = self.root / f"target-{index}"
                source_parent.mkdir()
                target_parent.mkdir()
                source = source_parent / "staged"
                source.mkdir()
                (source / "payload").write_text("approved")
                identity = self.identity(source)
                try:
                    adapter(
                        self.open_parent(source_parent),
                        "staged",
                        self.open_parent(target_parent),
                        "published",
                    )
                except OSError as error:
                    self.fail(f"native exclusive directory publication failed: {error}")
                self.assertFalse(source.exists())
                self.assertEqual(self.identity(target_parent / "published"), identity)
                self.assertEqual(
                    (target_parent / "published" / "payload").read_text(), "approved"
                )

    def test_existing_entries_and_aliases_preserve_source_and_destination(self) -> None:
        for index, adapter in enumerate(self.adapters):
            for kind in (
                "file",
                "directory",
                "broken-symlink",
                "hardlink",
                "same-name",
                "same-parent-two-fds",
                "case-alias",
                "normalization-alias",
            ):
                with self.subTest(adapter=adapter.__module__, kind=kind):
                    parent = self.root / f"{index}-{kind}"
                    parent.mkdir()
                    source_name = (
                        "caf\u00e9" if kind == "normalization-alias" else "source"
                    )
                    target_name = {
                        "same-name": source_name,
                        "same-parent-two-fds": source_name,
                        "case-alias": "SOURCE",
                        "normalization-alias": "cafe\u0301",
                    }.get(kind, "destination")
                    source = parent / source_name
                    source.write_text("source payload")
                    target = parent / target_name
                    if kind == "directory":
                        target.mkdir()
                    elif kind == "broken-symlink":
                        target.symlink_to("absent")
                    elif kind == "hardlink":
                        os.link(source, target)
                    elif not target.exists():
                        target.write_text("destination payload")
                    source_identity, target_identity = (
                        self.identity(source),
                        self.identity(target),
                    )
                    source_fd = self.open_parent(parent)
                    target_fd = (
                        self.open_parent(parent)
                        if kind == "same-parent-two-fds"
                        else source_fd
                    )
                    with self.assertRaises(FileExistsError):
                        adapter(source_fd, source_name, target_fd, target_name)
                    self.assertEqual(self.identity(source), source_identity)
                    self.assertEqual(self.identity(target), target_identity)
                    self.assertEqual(source.read_text(), "source payload")

    def test_missing_source_does_not_create_destination(self) -> None:
        parent = self.open_parent(self.root)
        for adapter in self.adapters:
            with self.subTest(adapter=adapter.__module__):
                with self.assertRaises(FileNotFoundError):
                    adapter(parent, "absent", parent, "destination")
                self.assertFalse((self.root / "destination").exists())

    def test_destination_created_after_guard_is_not_overwritten(self) -> None:
        original_encode = os.fsencode
        for index, adapter in enumerate(self.adapters):
            with self.subTest(adapter=adapter.__module__):
                parent = self.root / str(index)
                parent.mkdir()
                source = parent / "source"
                target = parent / "target"
                source.write_text("source")
                descriptor = self.open_parent(parent)
                created = False

                def racing_encode(path):
                    nonlocal created
                    if path == "target" and not created:
                        created = True
                        target.write_text("racing destination")
                    return original_encode(path)

                with mock.patch.object(os, "fsencode", side_effect=racing_encode):
                    with self.assertRaises(FileExistsError):
                        adapter(descriptor, "source", descriptor, "target")
                self.assertEqual(source.read_text(), "source")
                self.assertTrue(created)
                self.assertEqual(target.read_text(), "racing destination")

    def test_unsupported_exclusive_syscall_keeps_source_and_destination_absent(
        self,
    ) -> None:
        parent = self.open_parent(self.root)
        source = self.root / "source"
        source.write_text("must remain")
        original = self.identity(source)
        for module in (repositories, transaction, profile_snapshot):
            for code in (errno.ENOSYS, errno.EINVAL, errno.ENOTSUP):
                with self.subTest(module=module.__name__, errno=code):

                    def unsupported(*_args):
                        module.ctypes.set_errno(code)
                        return -1

                    if module is profile_snapshot:
                        adapter = module._rename_noreplace_at
                        patcher = mock.patch.object(
                            module.ctypes,
                            "CDLL",
                            return_value=SimpleNamespace(
                                renameat2=unsupported, renameatx_np=unsupported
                            ),
                        )
                    else:
                        adapter = module._rename_noreplace
                        patcher = mock.patch.object(module, "_renameat2", unsupported)
                    with patcher:
                        with self.assertRaises(OSError) as caught:
                            adapter(parent, "source", parent, "destination")
                    self.assertEqual(caught.exception.errno, code)
                    self.assertEqual(self.identity(source), original)
                    self.assertEqual(source.read_text(), "must remain")
                    self.assertFalse((self.root / "destination").exists())

    def test_hardlink_destination_racing_after_guard_is_rejected(self) -> None:
        original_encode = os.fsencode
        for index, adapter in enumerate(self.adapters):
            with self.subTest(adapter=adapter.__module__):
                parent = self.root / str(index)
                parent.mkdir()
                source, target = parent / "source", parent / "target"
                source.write_text("source")
                original = self.identity(source)
                descriptor = self.open_parent(parent)
                linked = False

                def racing_encode(path):
                    nonlocal linked
                    if path == "target" and not linked:
                        linked = True
                        os.link(source, target)
                    return original_encode(path)

                with mock.patch.object(os, "fsencode", side_effect=racing_encode):
                    with self.assertRaises(FileExistsError):
                        adapter(descriptor, "source", descriptor, "target")
                self.assertTrue(linked)
                self.assertEqual(self.identity(source), original)
                self.assertEqual(self.identity(target), original)
