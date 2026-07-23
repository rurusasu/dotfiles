"""Descriptor-anchored filesystem helpers for private bootstrap state."""

from __future__ import annotations

import ctypes
import errno
import os
import secrets
import stat
from dataclasses import dataclass
from pathlib import Path
from typing import Any


_RENAME_NOREPLACE = 1
_PRIVATE_DIRECTORY_ATTEMPTS = 32
_CLEANUP_QUARANTINE_ATTEMPTS = 32


def _load_renameat2() -> Any | None:
    try:
        function = ctypes.CDLL(None, use_errno=True).renameat2
    except (AttributeError, OSError):
        return None
    function.argtypes = (
        ctypes.c_int,
        ctypes.c_char_p,
        ctypes.c_int,
        ctypes.c_char_p,
        ctypes.c_uint,
    )
    function.restype = ctypes.c_int
    return function


_renameat2 = _load_renameat2()


def _private_cleanup_checkpoint(
    _kind: str,
    _parent_fd: int,
    _name: str,
) -> None:
    pass


@dataclass
class PrivateDirectory:
    """Own one private temporary directory by its retained descriptors."""

    path: Path
    _parent_fd: int
    _directory_fd: int
    _parent_identity: tuple[int, int]
    _identity: tuple[int, int]
    _active: bool = True

    @property
    def identity(self) -> tuple[int, int]:
        return self._identity

    def cleanup(self) -> bool:
        """Delete only the captured directory tree and report any replacement."""

        if not self._active:
            return True
        success = False
        try:
            _require_directory_identity(self._parent_fd, self._parent_identity)
            verify_absolute_directory(self.path.parent, self._parent_fd)
            _require_directory_identity(self._directory_fd, self._identity)
            path_changed = not _entry_matches(
                self._parent_fd,
                self.path.name,
                self._identity,
                directory=True,
            )
            if _find_directory_name(
                self._parent_fd,
                self._identity,
            ) is None:
                raise OSError("private cleanup target is unavailable")
            _clear_directory(
                self._directory_fd,
                self._identity,
                self._identity[0],
            )
            verify_absolute_directory(self.path.parent, self._parent_fd)
            path_changed = path_changed or not _entry_matches(
                self._parent_fd,
                self.path.name,
                self._identity,
                directory=True,
            )
            current_name = _find_directory_name(
                self._parent_fd,
                self._identity,
            )
            if current_name is None:
                raise OSError("private cleanup target is unavailable")
            _remove_directory_entry(
                self._parent_fd,
                current_name,
                self._directory_fd,
                self._identity,
            )
            try:
                os.stat(
                    self.path.name,
                    dir_fd=self._parent_fd,
                    follow_symlinks=False,
                )
            except FileNotFoundError:
                pass
            else:
                path_changed = True
            if _find_directory_name(self._parent_fd, self._identity) is not None:
                raise OSError("private cleanup target remains")
            success = not path_changed
        except Exception:
            success = False
        finally:
            self._close()
        return success

    def release(self) -> None:
        """Relinquish cleanup ownership after a verified publication move."""

        self._close()

    def _close(self) -> None:
        if not self._active:
            return
        self._active = False
        try:
            os.close(self._directory_fd)
        finally:
            os.close(self._parent_fd)


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


def create_private_directory(parent: Path, *, prefix: str) -> PrivateDirectory:
    """Create and retain one mode-0700 directory beneath an absolute parent."""

    if (
        not prefix
        or "/" in prefix
        or "\0" in prefix
        or prefix in {".", ".."}
    ):
        raise ValueError("private directory prefix is invalid")
    parent_fd = open_absolute_directory(parent)
    directory_fd: int | None = None
    created_name: str | None = None
    try:
        parent_status = os.fstat(parent_fd)
        parent_identity = (parent_status.st_dev, parent_status.st_ino)
        for _attempt in range(_PRIVATE_DIRECTORY_ATTEMPTS):
            candidate = f"{prefix}{secrets.token_hex(16)}"
            try:
                os.mkdir(candidate, mode=0o700, dir_fd=parent_fd)
            except FileExistsError:
                continue
            created_name = candidate
            break
        if created_name is None:
            raise OSError("private directory name is unavailable")
        directory_fd = _open_directory_at(parent_fd, created_name)
        current = os.stat(
            created_name,
            dir_fd=parent_fd,
            follow_symlinks=False,
        )
        opened = os.fstat(directory_fd)
        identity = (opened.st_dev, opened.st_ino)
        if (
            not stat.S_ISDIR(current.st_mode)
            or (current.st_dev, current.st_ino) != identity
            or stat.S_IMODE(opened.st_mode) != 0o700
        ):
            raise OSError("private directory changed during creation")
        verify_absolute_directory(parent, parent_fd)
        result = PrivateDirectory(
            parent / created_name,
            parent_fd,
            directory_fd,
            parent_identity,
            identity,
        )
        parent_fd = -1
        directory_fd = None
        return result
    except Exception:
        if created_name is not None and directory_fd is not None:
            status = os.fstat(directory_fd)
            owner = PrivateDirectory(
                parent / created_name,
                os.dup(parent_fd),
                directory_fd,
                (os.fstat(parent_fd).st_dev, os.fstat(parent_fd).st_ino),
                (status.st_dev, status.st_ino),
            )
            directory_fd = None
            owner.cleanup()
        raise
    finally:
        if directory_fd is not None:
            os.close(directory_fd)
        if parent_fd >= 0:
            os.close(parent_fd)


def _open_directory_at(parent_fd: int, name: str) -> int:
    flags = (
        os.O_RDONLY
        | os.O_CLOEXEC
        | getattr(os, "O_DIRECTORY", 0)
        | getattr(os, "O_NOFOLLOW", 0)
        | getattr(os, "O_NONBLOCK", 0)
    )
    return os.open(name, flags, dir_fd=parent_fd)


def _require_directory_identity(
    descriptor: int,
    expected: tuple[int, int],
) -> os.stat_result:
    current = os.fstat(descriptor)
    if (
        not stat.S_ISDIR(current.st_mode)
        or (current.st_dev, current.st_ino) != expected
    ):
        raise OSError("private directory identity changed")
    return current


def _entry_matches(
    parent_fd: int,
    name: str,
    expected: tuple[int, int],
    *,
    directory: bool,
) -> bool:
    try:
        current = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    except FileNotFoundError:
        return False
    return (
        stat.S_ISDIR(current.st_mode) == directory
        and (current.st_dev, current.st_ino) == expected
    )


def _find_directory_name(
    parent_fd: int,
    expected: tuple[int, int],
) -> str | None:
    with os.scandir(parent_fd) as iterator:
        names = sorted(entry.name for entry in iterator)
    found: str | None = None
    for name in names:
        try:
            current = os.stat(
                name,
                dir_fd=parent_fd,
                follow_symlinks=False,
            )
        except FileNotFoundError:
            continue
        if (
            stat.S_ISDIR(current.st_mode)
            and (current.st_dev, current.st_ino) == expected
        ):
            if found is not None:
                raise OSError("private cleanup target is ambiguous")
            found = name
    return found


def _clear_directory(
    directory_fd: int,
    expected: tuple[int, int],
    root_device: int,
) -> None:
    _require_directory_identity(directory_fd, expected)
    with os.scandir(directory_fd) as iterator:
        names = sorted(entry.name for entry in iterator)
    failed = False
    for name in names:
        try:
            current = os.stat(
                name,
                dir_fd=directory_fd,
                follow_symlinks=False,
            )
            if current.st_dev != root_device:
                raise OSError("private cleanup crossed a device boundary")
            identity = (current.st_dev, current.st_ino)
            if stat.S_ISDIR(current.st_mode):
                child_fd = _open_directory_at(directory_fd, name)
                try:
                    _require_directory_identity(child_fd, identity)
                    _clear_directory(child_fd, identity, root_device)
                    _remove_directory_entry(
                        directory_fd,
                        name,
                        child_fd,
                        identity,
                    )
                finally:
                    os.close(child_fd)
            else:
                _remove_nondirectory_entry(
                    directory_fd,
                    name,
                    current,
                )
        except Exception:
            failed = True
    _require_directory_identity(directory_fd, expected)
    with os.scandir(directory_fd) as iterator:
        remaining = next(iterator, None) is not None
    if failed or remaining:
        raise OSError("private cleanup did not quiesce")


def _remove_directory_entry(
    parent_fd: int,
    name: str,
    descriptor: int,
    expected: tuple[int, int],
) -> None:
    _require_directory_identity(descriptor, expected)
    with os.scandir(descriptor) as iterator:
        if next(iterator, None) is not None:
            raise OSError("private cleanup directory is not empty")
    final_name = _transfer_twice(
        parent_fd,
        name,
        expected,
        directory=True,
    )
    _private_cleanup_checkpoint("directory", parent_fd, final_name)
    _require_directory_identity(descriptor, expected)
    if not _entry_matches(
        parent_fd,
        final_name,
        expected,
        directory=True,
    ):
        raise OSError("private cleanup directory changed")
    with os.scandir(descriptor) as iterator:
        if next(iterator, None) is not None:
            raise OSError("private cleanup directory changed")
    os.rmdir(final_name, dir_fd=parent_fd)


def _remove_nondirectory_entry(
    parent_fd: int,
    name: str,
    current: os.stat_result,
) -> None:
    expected = (current.st_dev, current.st_ino)
    descriptor: int | None = None
    if stat.S_ISREG(current.st_mode):
        flags = (
            os.O_RDONLY
            | os.O_CLOEXEC
            | getattr(os, "O_NOFOLLOW", 0)
            | getattr(os, "O_NONBLOCK", 0)
        )
        descriptor = os.open(name, flags, dir_fd=parent_fd)
        opened = os.fstat(descriptor)
        if (
            not stat.S_ISREG(opened.st_mode)
            or (opened.st_dev, opened.st_ino) != expected
        ):
            os.close(descriptor)
            raise OSError("private cleanup file changed")
    try:
        final_name = _transfer_twice(
            parent_fd,
            name,
            expected,
            directory=False,
        )
        _private_cleanup_checkpoint("entry", parent_fd, final_name)
        if not _entry_matches(
            parent_fd,
            final_name,
            expected,
            directory=False,
        ):
            raise OSError("private cleanup entry changed")
        if descriptor is not None:
            opened = os.fstat(descriptor)
            if (
                not stat.S_ISREG(opened.st_mode)
                or (opened.st_dev, opened.st_ino) != expected
            ):
                raise OSError("private cleanup file changed")
        os.unlink(final_name, dir_fd=parent_fd)
    finally:
        if descriptor is not None:
            os.close(descriptor)


def _transfer_twice(
    parent_fd: int,
    name: str,
    expected: tuple[int, int],
    *,
    directory: bool,
) -> str:
    first = _quarantine_entry(
        parent_fd,
        name,
        expected,
        directory=directory,
    )
    return _quarantine_entry(
        parent_fd,
        first,
        expected,
        directory=directory,
    )


def _quarantine_entry(
    parent_fd: int,
    name: str,
    expected: tuple[int, int],
    *,
    directory: bool,
) -> str:
    for _attempt in range(_CLEANUP_QUARANTINE_ATTEMPTS):
        quarantine = _unused_cleanup_name(parent_fd)
        try:
            _rename_noreplace_at(
                parent_fd,
                name,
                parent_fd,
                quarantine,
            )
        except FileExistsError:
            continue
        if not _entry_matches(
            parent_fd,
            quarantine,
            expected,
            directory=directory,
        ):
            try:
                _rename_noreplace_at(
                    parent_fd,
                    quarantine,
                    parent_fd,
                    name,
                )
            except OSError:
                pass
            raise OSError("private cleanup entry changed")
        return quarantine
    raise OSError("private cleanup quarantine is unavailable")


def _rename_noreplace_at(
    source_fd: int,
    source_name: str,
    destination_fd: int,
    destination_name: str,
) -> None:
    if _renameat2 is None:
        raise OSError(
            errno.ENOSYS,
            "atomic no-replace rename is unavailable",
        )
    ctypes.set_errno(0)
    result = _renameat2(
        source_fd,
        os.fsencode(source_name),
        destination_fd,
        os.fsencode(destination_name),
        _RENAME_NOREPLACE,
    )
    if result == 0:
        return
    error_number = ctypes.get_errno() or errno.EIO
    if error_number == errno.EEXIST:
        raise FileExistsError(
            error_number,
            "atomic no-replace destination exists",
        )
    raise OSError(error_number, "atomic no-replace rename failed")


def _unused_cleanup_name(parent_fd: int) -> str:
    for _attempt in range(_CLEANUP_QUARANTINE_ATTEMPTS):
        candidate = f".hermes-private-cleanup-{secrets.token_hex(16)}"
        try:
            os.stat(
                candidate,
                dir_fd=parent_fd,
                follow_symlinks=False,
            )
        except FileNotFoundError:
            return candidate
    raise OSError("private cleanup quarantine is unavailable")
