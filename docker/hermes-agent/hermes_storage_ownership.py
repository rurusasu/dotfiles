#!/usr/bin/env python3
"""Converge ownership within one Hermes data-volume filesystem."""

from __future__ import annotations

import argparse
import os
import stat
from collections.abc import Sequence
from pathlib import Path

_BASE_OPEN_FLAGS = os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW


def _identity(info: os.stat_result) -> tuple[int, int, int]:
    return (info.st_dev, info.st_ino, stat.S_IFMT(info.st_mode))


def _open_entry(parent_fd: int, name: str, mode: int) -> int:
    flags = _BASE_OPEN_FLAGS
    if stat.S_ISDIR(mode):
        flags |= os.O_DIRECTORY
    else:
        flags |= os.O_NONBLOCK
    return os.open(name, flags, dir_fd=parent_fd)


def _requires_ownership_change(
    info: os.stat_result,
    uid: int,
    gid: int,
) -> bool:
    return info.st_uid != uid or info.st_gid != gid


def _preflight_ownership(
    info: os.stat_result,
    uid: int,
    gid: int,
) -> None:
    if _requires_ownership_change(info, uid, gid) and info.st_mode & (
        stat.S_ISUID | stat.S_ISGID
    ):
        raise RuntimeError("ownership convergence would clear set-ID mode bits")


def _set_ownership(
    fd: int,
    before: os.stat_result,
    uid: int,
    gid: int,
) -> None:
    _preflight_ownership(before, uid, gid)
    if not _requires_ownership_change(before, uid, gid):
        return

    os.fchown(fd, uid, gid)
    after = os.fstat(fd)
    if after.st_uid != uid or after.st_gid != gid:
        raise RuntimeError("ownership convergence did not persist")
    if stat.S_IMODE(after.st_mode) != stat.S_IMODE(before.st_mode):
        raise RuntimeError("ownership convergence changed mode")
    if after.st_mtime_ns != before.st_mtime_ns:
        raise RuntimeError("ownership convergence changed mtime")


def _preflight_directory(
    directory_fd: int, root_device: int, uid: int, gid: int
) -> None:
    with os.scandir(directory_fd) as entries:
        snapshots = [
            (
                entry.name,
                os.stat(entry.name, dir_fd=directory_fd, follow_symlinks=False),
            )
            for entry in entries
        ]

    for name, before in snapshots:
        if before.st_dev != root_device:
            continue
        if not (stat.S_ISDIR(before.st_mode) or stat.S_ISREG(before.st_mode)):
            continue

        child_fd = _open_entry(directory_fd, name, before.st_mode)
        try:
            opened = os.fstat(child_fd)
            if _identity(opened) != _identity(before):
                raise RuntimeError(f"entry changed while opening: {name!r}")
            _preflight_ownership(opened, uid, gid)
            if stat.S_ISDIR(opened.st_mode):
                _preflight_directory(child_fd, root_device, uid, gid)
        finally:
            os.close(child_fd)


def _converge_directory(
    directory_fd: int, root_device: int, uid: int, gid: int
) -> None:
    with os.scandir(directory_fd) as entries:
        snapshots = [
            (
                entry.name,
                os.stat(entry.name, dir_fd=directory_fd, follow_symlinks=False),
            )
            for entry in entries
        ]

    for name, before in snapshots:
        if before.st_dev != root_device:
            continue
        if not (stat.S_ISDIR(before.st_mode) or stat.S_ISREG(before.st_mode)):
            continue

        child_fd = _open_entry(directory_fd, name, before.st_mode)
        try:
            opened = os.fstat(child_fd)
            if _identity(opened) != _identity(before):
                raise RuntimeError(f"entry changed while opening: {name!r}")
            if stat.S_ISDIR(opened.st_mode):
                _converge_directory(child_fd, root_device, uid, gid)
            _set_ownership(child_fd, opened, uid, gid)
        finally:
            os.close(child_fd)


def converge_ownership(target: Path | str, uid: int, gid: int) -> None:
    """Change ownership of regular files/directories without following links."""

    root_fd = os.open(os.fspath(target), _BASE_OPEN_FLAGS | os.O_DIRECTORY)
    try:
        root = os.fstat(root_fd)
        if not stat.S_ISDIR(root.st_mode):
            raise NotADirectoryError(os.fspath(target))
        _preflight_ownership(root, uid, gid)
        _preflight_directory(root_fd, root.st_dev, uid, gid)
        _converge_directory(root_fd, root.st_dev, uid, gid)
        _set_ownership(root_fd, root, uid, gid)
    finally:
        os.close(root_fd)


def _nonnegative_integer(value: str) -> int:
    parsed = int(value)
    if parsed < 0:
        raise argparse.ArgumentTypeError("must be non-negative")
    return parsed


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", required=True)
    parser.add_argument("--uid", required=True, type=_nonnegative_integer)
    parser.add_argument("--gid", required=True, type=_nonnegative_integer)
    arguments = parser.parse_args(argv)
    converge_ownership(arguments.target, arguments.uid, arguments.gid)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
