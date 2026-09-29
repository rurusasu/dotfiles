"""Process-wide lock for Hermes bootstrap mutations."""

from __future__ import annotations

import fcntl
import os
import stat
from dataclasses import dataclass
from pathlib import Path

from .errors import RepositoryError
from .filesystem import open_absolute_directory, verify_absolute_directory


_LOCK_NAME = "bootstrap-engine.lock"
_LOCK_MODE = 0o600


@dataclass
class EngineLock:
    """A descriptor-anchored, non-blocking lock for bootstrap mutations."""

    path: Path
    _data_root: Path
    _locks_path: Path
    _data_descriptor: int
    _locks_descriptor: int
    _file_descriptor: int
    _data_identity: tuple[int, int]
    _locks_identity: tuple[int, int]
    _file_identity: tuple[int, int]
    _closed: bool = False

    @classmethod
    def acquire(cls, data_root: Path) -> EngineLock:
        """Acquire the global bootstrap engine lock without waiting."""

        root = Path(data_root)
        locks_path = root / "locks"
        data_descriptor: int | None = None
        locks_descriptor: int | None = None
        file_descriptor: int | None = None
        try:
            data_descriptor = open_absolute_directory(root)
            locks_descriptor = open_absolute_directory(
                locks_path, create=True, mode=0o700
            )
            file_descriptor = _open_lock_file(locks_descriptor)
            data_identity = _directory_identity(data_descriptor)
            locks_identity = _directory_identity(locks_descriptor)
            file_identity = _file_identity(file_descriptor, locks_descriptor)
            _verify_paths(
                root,
                locks_path,
                data_descriptor,
                locks_descriptor,
                data_identity,
                locks_identity,
            )
            fcntl.flock(file_descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            _verify_paths(
                root,
                locks_path,
                data_descriptor,
                locks_descriptor,
                data_identity,
                locks_identity,
            )
            _require_file_identity(file_descriptor, locks_descriptor, file_identity)
            return cls(
                locks_path / _LOCK_NAME,
                root,
                locks_path,
                data_descriptor,
                locks_descriptor,
                file_descriptor,
                data_identity,
                locks_identity,
                file_identity,
            )
        except Exception:
            if file_descriptor is not None:
                _safe_close(file_descriptor)
            if locks_descriptor is not None:
                _safe_close(locks_descriptor)
            if data_descriptor is not None:
                _safe_close(data_descriptor)
            raise RepositoryError("bootstrap engine lock is unavailable") from None

    def require_held(self) -> None:
        """Require that the retained descriptors still identify the lock path."""

        try:
            if self._closed:
                raise ValueError
            _verify_paths(
                self._data_root,
                self._locks_path,
                self._data_descriptor,
                self._locks_descriptor,
                self._data_identity,
                self._locks_identity,
            )
            _require_file_identity(
                self._file_descriptor,
                self._locks_descriptor,
                self._file_identity,
            )
        except Exception:
            raise RepositoryError("bootstrap engine lock is unavailable") from None

    def close(self) -> None:
        """Release retained descriptors; closing more than once is harmless."""

        if self._closed:
            return
        self._closed = True
        try:
            fcntl.flock(self._file_descriptor, fcntl.LOCK_UN)
        except OSError:
            pass
        finally:
            _safe_close(self._file_descriptor)
            _safe_close(self._locks_descriptor)
            _safe_close(self._data_descriptor)

    def __enter__(self) -> EngineLock:
        return self

    def __exit__(self, kind: object, value: object, traceback: object) -> None:
        del kind, value, traceback
        self.close()


def _open_lock_file(locks_descriptor: int) -> int:
    flags = (
        os.O_RDWR
        | os.O_CLOEXEC
        | os.O_NONBLOCK
        | getattr(os, "O_NOFOLLOW", 0)
    )
    try:
        return os.open(
            _LOCK_NAME,
            flags | os.O_CREAT | os.O_EXCL,
            _LOCK_MODE,
            dir_fd=locks_descriptor,
        )
    except FileExistsError:
        return os.open(_LOCK_NAME, flags, dir_fd=locks_descriptor)


def _directory_identity(descriptor: int) -> tuple[int, int]:
    info = os.fstat(descriptor)
    if not stat.S_ISDIR(info.st_mode):
        raise ValueError
    return info.st_dev, info.st_ino


def _file_identity(file_descriptor: int, locks_descriptor: int) -> tuple[int, int]:
    info = _require_safe_file(file_descriptor)
    entry = os.stat(_LOCK_NAME, dir_fd=locks_descriptor, follow_symlinks=False)
    if not _is_safe_file(entry) or (entry.st_dev, entry.st_ino) != (
        info.st_dev,
        info.st_ino,
    ):
        raise ValueError
    return info.st_dev, info.st_ino


def _verify_paths(
    data_root: Path,
    locks_path: Path,
    data_descriptor: int,
    locks_descriptor: int,
    data_identity: tuple[int, int],
    locks_identity: tuple[int, int],
) -> None:
    if _directory_identity(data_descriptor) != data_identity:
        raise ValueError
    if _directory_identity(locks_descriptor) != locks_identity:
        raise ValueError
    verify_absolute_directory(data_root, data_descriptor)
    verify_absolute_directory(locks_path, locks_descriptor)


def _require_file_identity(
    file_descriptor: int,
    locks_descriptor: int,
    expected: tuple[int, int],
) -> None:
    current = _file_identity(file_descriptor, locks_descriptor)
    if current != expected:
        raise ValueError


def _require_safe_file(descriptor: int) -> os.stat_result:
    info = os.fstat(descriptor)
    if not _is_safe_file(info):
        raise ValueError
    return info


def _is_safe_file(info: os.stat_result) -> bool:
    return (
        stat.S_ISREG(info.st_mode)
        and info.st_uid == os.geteuid()
        and info.st_nlink == 1
        and stat.S_IMODE(info.st_mode) == _LOCK_MODE
    )


def _safe_close(descriptor: int) -> None:
    try:
        os.close(descriptor)
    except OSError:
        pass
