"""Descriptor-anchored filesystem helpers for private bootstrap state."""

from __future__ import annotations

import os
import stat
from pathlib import Path


def open_absolute_directory(path: Path, *, create: bool = False, mode: int = 0o700) -> int:
    """Open an absolute directory without following any path-component symlink."""

    normalized = Path(os.path.normpath(path))
    if not path.is_absolute() or path != normalized or path.anchor != "/":
        raise ValueError("directory path is not canonical")

    flags = os.O_RDONLY | os.O_CLOEXEC | getattr(os, "O_DIRECTORY", 0)
    nofollow = getattr(os, "O_NOFOLLOW", 0)
    descriptor: int | None = os.open("/", flags | nofollow)
    try:
        for component in path.parts[1:]:
            try:
                child = os.open(component, flags | nofollow, dir_fd=descriptor)
            except FileNotFoundError:
                if not create:
                    raise
                try:
                    os.mkdir(component, mode=mode, dir_fd=descriptor)
                except FileExistsError:
                    pass
                child = os.open(component, flags | nofollow, dir_fd=descriptor)
            try:
                path_info = os.stat(component, dir_fd=descriptor, follow_symlinks=False)
                opened = os.fstat(child)
                if (
                    stat.S_ISLNK(path_info.st_mode)
                    or not stat.S_ISDIR(opened.st_mode)
                    or (path_info.st_dev, path_info.st_ino) != (opened.st_dev, opened.st_ino)
                ):
                    raise ValueError("directory path is unsafe")
            except Exception:
                os.close(child)
                raise
            os.close(descriptor)
            descriptor = child
        result = descriptor
        descriptor = None
        return result
    finally:
        if descriptor is not None:
            os.close(descriptor)


def verify_absolute_directory(path: Path, descriptor: int) -> None:
    """Require the current absolute path to identify the already-open directory."""

    current = open_absolute_directory(path)
    try:
        expected = os.fstat(descriptor)
        actual = os.fstat(current)
        if (expected.st_dev, expected.st_ino) != (actual.st_dev, actual.st_ino):
            raise ValueError("directory path changed")
    finally:
        os.close(current)
