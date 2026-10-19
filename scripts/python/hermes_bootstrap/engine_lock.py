"""Process-wide lock for Hermes bootstrap mutations."""

from __future__ import annotations

import fcntl
import os
import stat
from dataclasses import dataclass
from pathlib import Path
from typing import Self

from .errors import RepositoryError
from .filesystem import open_absolute_directory

_LOCK_NAME = "bootstrap-engine.lock"
_LOCK_MODE = 0o600


@dataclass
class EngineLock:
    """A non-blocking process lock for bootstrap mutations."""

    path: Path
    _file_descriptor: int
    _closed: bool = False

    @classmethod
    def acquire(cls, data_root: Path) -> Self:
        """Acquire the global bootstrap engine lock without waiting."""

        locks_path = Path(data_root) / "locks"
        locks_descriptor: int | None = None
        file_descriptor: int | None = None
        try:
            if not locks_path.parent.is_dir():
                raise ValueError("data root is unavailable")
            locks_descriptor = open_absolute_directory(
                locks_path, create=True, mode=0o700
            )
            file_descriptor = _open_lock_file(locks_descriptor)
            info = os.fstat(file_descriptor)
            if not (
                stat.S_ISREG(info.st_mode)
                and info.st_uid == os.geteuid()
                and info.st_nlink == 1
                and stat.S_IMODE(info.st_mode) == _LOCK_MODE
            ):
                raise ValueError("lock file is unsafe")
            fcntl.flock(file_descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return cls(locks_path / _LOCK_NAME, file_descriptor)
        except (OSError, ValueError):
            if file_descriptor is not None:
                _safe_close(file_descriptor)
            raise RepositoryError("bootstrap engine lock is unavailable") from None
        finally:
            if locks_descriptor is not None:
                _safe_close(locks_descriptor)

    def require_held(self) -> None:
        """Require that this instance still holds its lock."""

        if self._closed:
            raise RepositoryError("bootstrap engine lock is unavailable")

    def close(self) -> None:
        """Release the lock; closing more than once is harmless."""

        if self._closed:
            return
        self._closed = True
        # Closing the descriptor releases flock even when explicit unlock fails.
        try:
            fcntl.flock(self._file_descriptor, fcntl.LOCK_UN)
        except OSError:
            pass
        finally:
            _safe_close(self._file_descriptor)

    def __enter__(self) -> Self:
        self.require_held()
        return self

    def __exit__(self, kind: object, value: object, traceback: object) -> None:
        del kind, value, traceback
        self.close()


def _open_lock_file(locks_descriptor: int) -> int:
    flags = os.O_RDWR | os.O_CLOEXEC | os.O_NONBLOCK | getattr(os, "O_NOFOLLOW", 0)
    try:
        return os.open(
            _LOCK_NAME,
            flags | os.O_CREAT | os.O_EXCL,
            _LOCK_MODE,
            dir_fd=locks_descriptor,
        )
    except FileExistsError:
        return os.open(_LOCK_NAME, flags, dir_fd=locks_descriptor)


def _safe_close(descriptor: int) -> None:
    # Descriptor cleanup must not replace the redacted acquisition failure.
    try:
        os.close(descriptor)
    except OSError:
        pass
