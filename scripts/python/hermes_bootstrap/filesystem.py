"""Filesystem helpers for private bootstrap temporary directories."""

from __future__ import annotations

import os
import shutil
import stat
import tempfile
from dataclasses import dataclass
from pathlib import Path


@dataclass
class PrivateDirectory:
    """Own a private temporary directory until cleanup or publication."""

    path: Path

    def cleanup(self) -> bool:
        """Remove this temporary tree and report failures without path details."""

        try:
            # rmtree unlinks symlinks and special entries without opening targets.
            shutil.rmtree(self.path)
        except FileNotFoundError:
            return True
        except OSError:
            return False
        return True


def open_absolute_directory(
    path: Path, *, create: bool = False, mode: int = 0o700
) -> int:
    """Validate a canonical directory path and return an open descriptor."""

    _validate_absolute_directory(path, create=create, mode=mode)
    flags = (
        os.O_RDONLY
        | os.O_CLOEXEC
        | getattr(os, "O_DIRECTORY", 0)
        | getattr(os, "O_NOFOLLOW", 0)
    )
    return os.open(path, flags)


def create_private_directory(parent: Path, *, prefix: str) -> PrivateDirectory:
    """Create one mode-0700 temporary directory beneath an absolute parent."""

    if not prefix or "/" in prefix or "\0" in prefix or prefix in {".", ".."}:
        raise ValueError("private directory prefix is invalid")
    _validate_absolute_directory(parent)
    path = Path(tempfile.mkdtemp(prefix=prefix, dir=parent))
    return PrivateDirectory(path)


def _validate_absolute_directory(
    path: Path, *, create: bool = False, mode: int = 0o700
) -> None:
    if (
        not path.is_absolute()
        or path != Path(os.path.normpath(path))
        or path.anchor != "/"
    ):
        raise ValueError("directory path is not canonical")
    current = Path(path.anchor)
    for component in path.parts[1:]:
        current /= component
        try:
            status = current.lstat()
        except FileNotFoundError:
            if not create:
                raise
            try:
                current.mkdir(mode=mode)
            except FileExistsError:
                pass
            status = current.lstat()
        if not stat.S_ISDIR(status.st_mode):
            raise ValueError("directory path is unsafe")
