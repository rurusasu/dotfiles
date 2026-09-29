"""Descriptor-anchored filesystem helpers for private bootstrap state."""

from __future__ import annotations

import os
import secrets
import stat
import sys
from dataclasses import dataclass
from enum import Enum
from pathlib import Path


_PRIVATE_DIRECTORY_ATTEMPTS = 32


class _PrivateDirectoryState(Enum):
    ACTIVE = "active"
    CLEANED = "cleaned"
    RELEASED = "released"
    FAILED = "failed"


@dataclass(frozen=True)
class _CapturedDirectory:
    identity: tuple[int, int]
    entries: tuple[_CapturedEntry, ...]


@dataclass(frozen=True)
class _CapturedEntry:
    name: str
    identity: tuple[int, int]
    directory: _CapturedDirectory | None


@dataclass
class PrivateDirectory:
    """Own one private temporary directory by its retained descriptors."""

    path: Path
    _parent_fd: int
    _directory_fd: int
    _parent_identity: tuple[int, int]
    _identity: tuple[int, int]
    _mount_id: int | None
    _state: _PrivateDirectoryState = _PrivateDirectoryState.ACTIVE

    @property
    def identity(self) -> tuple[int, int]:
        return self._identity

    @property
    def is_released(self) -> bool:
        """Report whether verified publication transferred cleanup ownership."""

        return self._state is _PrivateDirectoryState.RELEASED

    def cleanup(self) -> bool:
        """Delete a fully validated captured tree and retain uncertain artifacts."""

        if self._state is _PrivateDirectoryState.CLEANED:
            return True
        if self._state is not _PrivateDirectoryState.ACTIVE:
            return False
        try:
            _require_directory_identity(self._parent_fd, self._parent_identity)
            verify_absolute_directory(self.path.parent, self._parent_fd)
            _require_directory_entry(
                self._parent_fd,
                self.path.name,
                self._identity,
            )
            root_status = _require_captured_directory(
                self._directory_fd,
                self._identity,
                self._identity[0],
                self._mount_id,
            )
            captured = _preflight_directory(
                self._directory_fd,
                self._identity,
                root_status.st_dev,
                self._mount_id,
            )
            _require_directory_identity(self._parent_fd, self._parent_identity)
            verify_absolute_directory(self.path.parent, self._parent_fd)
            _require_directory_entry(
                self._parent_fd,
                self.path.name,
                self._identity,
            )
            _remove_captured_directory_contents(
                self._directory_fd,
                captured,
                root_status.st_dev,
                self._mount_id,
            )
            _require_directory_identity(self._parent_fd, self._parent_identity)
            verify_absolute_directory(self.path.parent, self._parent_fd)
            _require_directory_entry(
                self._parent_fd,
                self.path.name,
                self._identity,
            )
            _require_captured_directory(
                self._directory_fd,
                self._identity,
                root_status.st_dev,
                self._mount_id,
            )
            if _scan_directory_names(self._directory_fd):
                raise OSError("private cleanup directory is not empty")
            os.rmdir(self.path.name, dir_fd=self._parent_fd)
            self._state = _PrivateDirectoryState.CLEANED
        except Exception:
            self._state = _PrivateDirectoryState.FAILED
        finally:
            try:
                self._close_descriptors()
            except Exception:
                self._state = _PrivateDirectoryState.FAILED
        return self._state is _PrivateDirectoryState.CLEANED

    def release(self) -> None:
        """Relinquish cleanup ownership after a verified publication move."""

        if self._state is not _PrivateDirectoryState.ACTIVE:
            return
        try:
            self._close_descriptors()
        except Exception:
            self._state = _PrivateDirectoryState.FAILED
            return
        self._state = _PrivateDirectoryState.RELEASED

    def _close_descriptors(self) -> None:
        failure: OSError | None = None
        for attribute in ("_directory_fd", "_parent_fd"):
            descriptor = getattr(self, attribute)
            if descriptor < 0:
                continue
            setattr(self, attribute, -1)
            try:
                os.close(descriptor)
            except OSError as error:
                if failure is None:
                    failure = error
        if failure is not None:
            raise failure


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
    mount_id: int | None = None
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
        mount_id = _descriptor_mount_id(directory_fd)
        verify_absolute_directory(parent, parent_fd)
        result = PrivateDirectory(
            path=parent / created_name,
            _parent_fd=parent_fd,
            _directory_fd=directory_fd,
            _parent_identity=parent_identity,
            _identity=identity,
            _mount_id=mount_id,
        )
        parent_fd = -1
        directory_fd = None
        return result
    except Exception:
        if created_name is not None and directory_fd is not None:
            status = os.fstat(directory_fd)
            owner = PrivateDirectory(
                path=parent / created_name,
                _parent_fd=os.dup(parent_fd),
                _directory_fd=directory_fd,
                _parent_identity=(
                    os.fstat(parent_fd).st_dev,
                    os.fstat(parent_fd).st_ino,
                ),
                _identity=(status.st_dev, status.st_ino),
                _mount_id=mount_id,
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


def _open_regular_at(parent_fd: int, name: str) -> int:
    flags = (
        os.O_RDONLY
        | os.O_CLOEXEC
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


def _require_directory_entry(
    parent_fd: int,
    name: str,
    expected: tuple[int, int],
) -> os.stat_result:
    current = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    if (
        not stat.S_ISDIR(current.st_mode)
        or (current.st_dev, current.st_ino) != expected
    ):
        raise OSError("private cleanup directory entry changed")
    return current


def _require_regular_entry(
    parent_fd: int,
    name: str,
    expected: tuple[int, int],
) -> os.stat_result:
    current = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    if (
        not stat.S_ISREG(current.st_mode)
        or current.st_nlink != 1
        or (current.st_dev, current.st_ino) != expected
    ):
        raise OSError("private cleanup regular file changed")
    return current


def _require_captured_directory(
    descriptor: int,
    expected: tuple[int, int],
    root_device: int,
    root_mount_id: int | None,
) -> os.stat_result:
    current = _require_directory_identity(descriptor, expected)
    if current.st_dev != root_device:
        raise OSError("private cleanup crossed a device boundary")
    _require_captured_mount(descriptor, root_mount_id)
    return current


def _require_captured_regular(
    descriptor: int,
    expected: tuple[int, int],
    root_device: int,
    root_mount_id: int | None,
) -> os.stat_result:
    current = os.fstat(descriptor)
    if (
        not stat.S_ISREG(current.st_mode)
        or current.st_nlink != 1
        or (current.st_dev, current.st_ino) != expected
    ):
        raise OSError("private cleanup regular file identity changed")
    if current.st_dev != root_device:
        raise OSError("private cleanup crossed a device boundary")
    _require_captured_mount(descriptor, root_mount_id)
    return current


def _require_captured_mount(
    descriptor: int,
    root_mount_id: int | None,
) -> None:
    current_mount_id = _descriptor_mount_id(descriptor)
    if sys.platform.startswith("linux") and (
        root_mount_id is None or current_mount_id is None
    ):
        raise OSError("private cleanup mount information is unavailable")
    if current_mount_id != root_mount_id:
        raise OSError("private cleanup crossed a mount boundary")


def _descriptor_mount_id(descriptor: int) -> int | None:
    if not sys.platform.startswith("linux"):
        return None
    try:
        with open(
            f"/proc/self/fdinfo/{descriptor}",
            "r",
            encoding="ascii",
        ) as stream:
            contents = stream.read(4097)
    except (OSError, UnicodeError) as error:
        raise OSError("private cleanup mount information is unavailable") from error
    if len(contents) > 4096:
        raise OSError("private cleanup mount information is malformed")
    values: list[int] = []
    for line in contents.splitlines():
        key, separator, raw_value = line.partition(":")
        if key != "mnt_id":
            continue
        value = raw_value.strip()
        if separator != ":" or not value.isascii() or not value.isdecimal():
            raise OSError("private cleanup mount information is malformed")
        values.append(int(value))
    if len(values) != 1:
        raise OSError("private cleanup mount information is malformed")
    return values[0]


def _scan_directory_names(directory_fd: int) -> tuple[str, ...]:
    with os.scandir(directory_fd) as iterator:
        return tuple(sorted(entry.name for entry in iterator))


def _preflight_directory(
    directory_fd: int,
    expected: tuple[int, int],
    root_device: int,
    root_mount_id: int | None,
) -> _CapturedDirectory:
    _require_captured_directory(
        directory_fd,
        expected,
        root_device,
        root_mount_id,
    )
    captured: list[_CapturedEntry] = []
    for name in _scan_directory_names(directory_fd):
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
                _require_captured_directory(
                    child_fd,
                    identity,
                    root_device,
                    root_mount_id,
                )
                directory = _preflight_directory(
                    child_fd,
                    identity,
                    root_device,
                    root_mount_id,
                )
            finally:
                os.close(child_fd)
            captured.append(_CapturedEntry(name, identity, directory))
            continue
        if not stat.S_ISREG(current.st_mode) or current.st_nlink != 1:
            raise OSError("private cleanup entry type is unsupported")
        child_fd = _open_regular_at(directory_fd, name)
        try:
            _require_captured_regular(
                child_fd,
                identity,
                root_device,
                root_mount_id,
            )
        finally:
            os.close(child_fd)
        captured.append(_CapturedEntry(name, identity, None))
    _require_captured_directory(
        directory_fd,
        expected,
        root_device,
        root_mount_id,
    )
    return _CapturedDirectory(expected, tuple(captured))


def _remove_captured_directory_contents(
    directory_fd: int,
    captured: _CapturedDirectory,
    root_device: int,
    root_mount_id: int | None,
) -> None:
    _require_captured_directory(
        directory_fd,
        captured.identity,
        root_device,
        root_mount_id,
    )
    if _scan_directory_names(directory_fd) != tuple(
        entry.name for entry in captured.entries
    ):
        raise OSError("private cleanup directory contents changed")
    for entry in captured.entries:
        if entry.directory is not None:
            _require_directory_entry(
                directory_fd,
                entry.name,
                entry.identity,
            )
            child_fd = _open_directory_at(directory_fd, entry.name)
            try:
                _require_captured_directory(
                    child_fd,
                    entry.identity,
                    root_device,
                    root_mount_id,
                )
                _remove_captured_directory_contents(
                    child_fd,
                    entry.directory,
                    root_device,
                    root_mount_id,
                )
                _require_directory_entry(
                    directory_fd,
                    entry.name,
                    entry.identity,
                )
                _require_captured_directory(
                    child_fd,
                    entry.identity,
                    root_device,
                    root_mount_id,
                )
                if _scan_directory_names(child_fd):
                    raise OSError("private cleanup directory is not empty")
                os.rmdir(entry.name, dir_fd=directory_fd)
            finally:
                os.close(child_fd)
            continue
        _require_regular_entry(
            directory_fd,
            entry.name,
            entry.identity,
        )
        child_fd = _open_regular_at(directory_fd, entry.name)
        try:
            _require_captured_regular(
                child_fd,
                entry.identity,
                root_device,
                root_mount_id,
            )
            _require_regular_entry(
                directory_fd,
                entry.name,
                entry.identity,
            )
            os.unlink(entry.name, dir_fd=directory_fd)
        finally:
            os.close(child_fd)
    _require_captured_directory(
        directory_fd,
        captured.identity,
        root_device,
        root_mount_id,
    )
    if _scan_directory_names(directory_fd):
        raise OSError("private cleanup directory is not empty")
