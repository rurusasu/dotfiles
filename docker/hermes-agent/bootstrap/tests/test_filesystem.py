from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


BOOTSTRAP_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BOOTSTRAP_ROOT))

from hermes_bootstrap import filesystem


class PrivateDirectoryTests(unittest.TestCase):
    def test_cleanup_fails_closed_for_replacement_created_at_final_checkpoint(
        self,
    ) -> None:
        marker = b"late-directory-replacement\n"
        with tempfile.TemporaryDirectory() as directory:
            parent = Path(directory).resolve()
            private = filesystem.create_private_directory(
                parent,
                prefix="late-cleanup-",
            )
            original_name = private.path.name
            checkpoints: list[tuple[str, str]] = []

            def replace_original(kind: str, parent_fd: int, name: str) -> None:
                checkpoints.append((kind, name))
                if kind != "directory":
                    return
                os.mkdir(original_name, mode=0o700, dir_fd=parent_fd)
                replacement_fd = os.open(
                    original_name,
                    os.O_RDONLY
                    | os.O_CLOEXEC
                    | getattr(os, "O_DIRECTORY", 0)
                    | getattr(os, "O_NOFOLLOW", 0),
                    dir_fd=parent_fd,
                )
                try:
                    marker_fd = os.open(
                        "marker",
                        os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC,
                        0o600,
                        dir_fd=replacement_fd,
                    )
                    try:
                        os.write(marker_fd, marker)
                    finally:
                        os.close(marker_fd)
                finally:
                    os.close(replacement_fd)

            with mock.patch.object(
                filesystem,
                "_private_cleanup_checkpoint",
                side_effect=replace_original,
            ):
                self.assertFalse(private.cleanup())

            self.assertEqual(len(checkpoints), 1)
            self.assertEqual(checkpoints[0][0], "directory")
            self.assertNotEqual(checkpoints[0][1], original_name)
            self.assertEqual((parent / original_name / "marker").read_bytes(), marker)


if __name__ == "__main__":
    unittest.main()
