"""Crash-recoverable local transactions for Hermes bootstrap mutations."""

from __future__ import annotations

import ctypes
import errno
import fcntl
import json
import os
import re
import shutil
import stat
import tempfile
import uuid
from pathlib import Path
from typing import Any, Callable

from .errors import ApplyError, RollbackError


_VERSION = 1
_JOURNAL_NAME = "journal.json"
_LOCK_NAME = ".lock"
_TRANSACTION_ID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\Z")
_BACKUP_ID = re.compile(r"backup-[0-9]{6}\Z")
_RENAME_NOREPLACE = 1
_failpoint: Callable[[str], None] = lambda _name: None


def _load_renameat2() -> Any | None:
    try:
        libc = ctypes.CDLL(None, use_errno=True)
        function = libc.renameat2
        function.argtypes = (
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_uint,
        )
        function.restype = ctypes.c_int
        return function
    except (AttributeError, OSError, TypeError):
        return None


_renameat2 = _load_renameat2()


class Transaction:
    """A single-writer journal whose ready records can be replayed backwards."""

    def __init__(self, data_root: Path, store: Path, directory: Path, lock: int, journal: dict[str, Any]) -> None:
        self._data_root = data_root
        self._store = store
        self._directory = directory
        self._lock = lock
        self._journal = journal
        self._closed = False
        self._outcome: str | None = None

    @classmethod
    def begin(cls, data_root: Path) -> Transaction:
        root = _require_data_root(data_root)
        store = _open_store(root)
        lock = _acquire_lock(store)
        directory: Path | None = None
        try:
            if _journal_directories(store):
                raise ApplyError("a previous bootstrap transaction requires recovery")
            directory = store / str(uuid.uuid4())
            directory.mkdir(mode=0o700)
            _fsync_directory(store)
            journal: dict[str, Any] = {"version": _VERSION, "status": "active", "entries": []}
            tx = cls(root, store, directory, lock, journal)
            tx._write_journal()
            return tx
        except ApplyError:
            _safe_remove_empty_initial_transaction(directory, store)
            _release_lock(lock)
            raise
        except Exception:
            _safe_remove_empty_initial_transaction(directory, store)
            _release_lock(lock)
            raise ApplyError("could not begin bootstrap transaction") from None

    @staticmethod
    def recover_if_needed(data_root: Path) -> None:
        root = _require_data_root(data_root)
        store = _open_store(root)
        lock = _acquire_lock(store)
        try:
            for directory in _journal_directories(store):
                if not _lexists(directory / _JOURNAL_NAME):
                    _remove_empty_transaction(directory, store)
                    continue
                journal = _read_journal(directory)
                _validate_journal(root, directory, journal)
                tx = Transaction(root, store, directory, lock, journal)
                if journal["status"] == "committed":
                    tx._cleanup_or_raise()
                    continue
                if journal["status"] == "rolled_back":
                    tx._cleanup_or_raise()
                    continue
                tx._rollback_or_raise()
            _release_lock(lock)
        except (ApplyError, RollbackError):
            _release_lock(lock)
            raise
        except Exception:
            _release_lock(lock)
            raise ApplyError("could not recover bootstrap transaction") from None

    def snapshot(self, path: Path) -> None:
        self._require_active()
        relative = _managed_relative(self._data_root, self._store, path)
        if self._covered_by_snapshot(relative):
            return
        if self._overlaps_active_move(relative):
            raise ApplyError("snapshot follows managed move")
        if self._has_snapshot_descendant(relative):
            raise ApplyError("snapshot parent follows child")
        original = _entry_kind(path)
        try:
            entry: dict[str, Any] = {
                "kind": "snapshot",
                "path": relative,
                "state": "preparing",
                "original": original,
                "backup": f"backup-{len(self._journal['entries']):06d}",
            }
            self._journal["entries"].append(entry)
            self._write_journal()
            _publish_backup(path, self._directory / entry["backup"], original)
            entry["state"] = "ready"
            self._write_journal()
            _failpoint("entry-ready")
        except ApplyError:
            self._abandon()
            raise
        except Exception:
            self._abandon()
            raise ApplyError("could not snapshot managed path") from None

    def record_move(self, source: Path, target: Path) -> None:
        self._require_active()
        source_relative = _managed_relative(self._data_root, self._store, source)
        target_relative = _managed_relative(self._data_root, self._store, target)
        if _overlaps(source_relative, target_relative):
            raise ApplyError("managed move paths overlap")
        source_kind = _entry_kind(source)
        target_kind = _entry_kind(target)
        if source_kind == "absent" or (target_kind != "absent" and not self._covered_by_snapshot(target_relative)):
            raise ApplyError("managed move is unsafe")
        identity = _identity(source, source_kind)
        for existing in self._journal["entries"]:
            if existing["kind"] != "move" or existing["state"] == "restored":
                continue
            if source_relative in (existing["source"], existing["target"]) or target_relative in (existing["source"], existing["target"]):
                raise ApplyError("incompatible managed move")
        try:
            entry = {
                "kind": "move",
                "source": source_relative,
                "target": target_relative,
                "state": "preparing",
                "identity": identity,
            }
            self._journal["entries"].append(entry)
            self._write_journal()
            entry["state"] = "ready"
            self._write_journal()
            _failpoint("entry-ready")
        except ApplyError:
            self._abandon()
            raise
        except Exception:
            self._abandon()
            raise ApplyError("could not record managed move") from None

    def commit(self) -> None:
        if self._closed:
            if self._outcome == "committed":
                return
            raise ApplyError("cannot commit a rolled back transaction")
        if self._journal["status"] == "committed":
            try:
                self._cleanup_or_raise()
                self._outcome = "committed"
                self._closed = True
                self._release_lock()
                return
            except Exception:
                self._abandon()
                raise ApplyError("could not finalize bootstrap transaction") from None
        self._require_active()
        try:
            self._journal["status"] = "committed"
            self._write_journal()
            _failpoint("status-update")
            self._cleanup_or_raise()
            self._outcome = "committed"
            self._closed = True
            self._release_lock()
        except ApplyError:
            self._abandon()
            raise
        except Exception:
            self._abandon()
            raise ApplyError("could not finalize bootstrap transaction") from None

    def rollback(self) -> None:
        if self._closed:
            if self._outcome == "rolled_back":
                return
            raise ApplyError("cannot roll back a committed transaction")
        if self._journal["status"] == "committed":
            self._abandon()
            raise ApplyError("cannot roll back a committed transaction")
        self._require_active()
        try:
            self._rollback_or_raise()
            self._outcome = "rolled_back"
            self._closed = True
            self._release_lock()
        except RollbackError:
            self._abandon()
            raise
        except Exception:
            self._abandon()
            raise RollbackError("could not roll back managed paths") from None

    def _rollback_or_raise(self) -> None:
        try:
            if self._journal["status"] == "active":
                self._journal["status"] = "rolling_back"
                self._write_journal()
            elif self._journal["status"] != "rolling_back":
                raise ValueError
        except Exception:
            raise RollbackError("could not roll back managed paths")
        failures: list[str] = []
        for index in range(len(self._journal["entries"]) - 1, -1, -1):
            entry = self._journal["entries"][index]
            if entry["state"] != "ready":
                continue
            try:
                _failpoint("before-restore")
                if entry["kind"] == "snapshot":
                    _restore_snapshot(
                        self._data_root,
                        self._data_root / entry["path"],
                        self._directory / entry["backup"],
                        entry["original"],
                    )
                else:
                    _reverse_move(self._data_root, self._directory, index, entry)
                entry["state"] = "restored"
                self._write_journal()
            except Exception:
                failures.extend(_entry_paths(entry))
                break
        if failures:
            raise RollbackError("could not roll back managed paths: " + ", ".join(sorted(set(failures))))
        try:
            self._journal["status"] = "rolled_back"
            self._write_journal()
        except Exception:
            raise RollbackError("could not roll back managed paths") from None
        self._cleanup_or_raise()

    def _cleanup_or_raise(self) -> None:
        try:
            _cleanup_transaction(self._data_root, self._directory, self._store, self._journal)
        except Exception:
            raise ApplyError("could not clean up bootstrap transaction") from None

    def _write_journal(self) -> None:
        _atomic_write_json(self._directory / _JOURNAL_NAME, self._journal)
        _failpoint("journal-write")

    def _covered_by_snapshot(self, relative: str) -> bool:
        return any(
            entry["kind"] == "snapshot"
            and entry["state"] != "restored"
            and (entry["path"] == relative or _is_descendant(relative, entry["path"]))
            for entry in self._journal["entries"]
        )

    def _has_snapshot_descendant(self, relative: str) -> bool:
        return any(
            entry["kind"] == "snapshot" and entry["state"] != "restored" and _is_descendant(entry["path"], relative)
            for entry in self._journal["entries"]
        )

    def _overlaps_active_move(self, relative: str) -> bool:
        return any(
            entry["kind"] == "move"
            and entry["state"] != "restored"
            and (_overlaps(relative, entry["source"]) or _overlaps(relative, entry["target"]))
            for entry in self._journal["entries"]
        )

    def _require_active(self) -> None:
        if self._closed or self._journal["status"] != "active":
            raise ApplyError("bootstrap transaction is not active")

    def _abandon(self) -> None:
        self._closed = True
        self._outcome = "abandoned"
        self._release_lock()

    def _release_lock(self) -> None:
        if self._lock >= 0:
            _release_lock(self._lock)
            self._lock = -1

    def __del__(self) -> None:
        self._release_lock()


def _require_data_root(data_root: Path) -> Path:
    try:
        root = Path(data_root)
        if not root.is_absolute():
            raise ValueError
        info = root.lstat()
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
            raise ValueError
        return root
    except Exception:
        raise ApplyError("bootstrap data root is unsafe") from None


def _open_store(data_root: Path) -> Path:
    try:
        bootstrap = data_root / ".bootstrap"
        if _lexists(bootstrap):
            _require_directory(bootstrap)
        else:
            bootstrap.mkdir(mode=0o700)
            _fsync_directory(data_root)
        store = bootstrap / "transactions"
        if _lexists(store):
            _require_directory(store)
        else:
            store.mkdir(mode=0o700)
            _fsync_directory(bootstrap)
        return store
    except ApplyError:
        raise
    except Exception:
        raise ApplyError("bootstrap transaction store is unsafe") from None


def _acquire_lock(store: Path) -> int:
    descriptor: int | None = None
    try:
        lock_path = store / _LOCK_NAME
        before: os.stat_result | None = None
        if _lexists(lock_path):
            before = lock_path.lstat()
            if stat.S_ISLNK(before.st_mode) or not stat.S_ISREG(before.st_mode):
                raise OSError
        flags = os.O_RDWR | os.O_CREAT | os.O_CLOEXEC | getattr(os, "O_NOFOLLOW", 0)
        descriptor = os.open(lock_path, flags, 0o600)
        opened = os.fstat(descriptor)
        after = lock_path.lstat()
        if (
            not stat.S_ISREG(opened.st_mode)
            or opened.st_nlink != 1
            or stat.S_ISLNK(after.st_mode)
            or not stat.S_ISREG(after.st_mode)
            or after.st_nlink != 1
            or (opened.st_dev, opened.st_ino) != (after.st_dev, after.st_ino)
            or before is not None
            and (before.st_nlink != 1 or (before.st_dev, before.st_ino) != (opened.st_dev, opened.st_ino))
        ):
            raise OSError
        os.fchmod(descriptor, 0o600)
        os.fsync(descriptor)
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        _fsync_directory(store)
        return descriptor
    except Exception:
        if descriptor is not None:
            _safe_close(descriptor)
        raise ApplyError("bootstrap transaction is already active") from None


def _release_lock(descriptor: int) -> None:
    try:
        fcntl.flock(descriptor, fcntl.LOCK_UN)
    except OSError:
        pass
    _safe_close(descriptor)


def _journal_directories(store: Path) -> list[Path]:
    try:
        directories: list[Path] = []
        with os.scandir(store) as entries:
            for entry in entries:
                path = Path(entry.path)
                if entry.name == _LOCK_NAME:
                    if not entry.is_file(follow_symlinks=False):
                        raise ValueError
                    continue
                if not _TRANSACTION_ID.fullmatch(entry.name) or not entry.is_dir(follow_symlinks=False):
                    raise ValueError
                directories.append(path)
        return sorted(directories, key=lambda path: path.name)
    except Exception:
        raise ApplyError("bootstrap transaction store is unsafe") from None


def _managed_relative(data_root: Path, store: Path, path: Path) -> str:
    try:
        candidate = Path(path)
        if not candidate.is_absolute():
            raise ValueError
        relative = candidate.relative_to(data_root)
        if not relative.parts or any(part in {"", ".", ".."} for part in relative.parts):
            raise ValueError
        if relative.parts[:2] == (".bootstrap", "transactions"):
            raise ValueError
        current = data_root
        for part in relative.parts[:-1]:
            current /= part
            if _lexists(current):
                _require_directory(current)
        return relative.as_posix()
    except Exception:
        raise ApplyError("managed path is unsafe") from None


def _entry_kind(path: Path) -> str:
    try:
        info = path.lstat()
    except FileNotFoundError:
        return "absent"
    except OSError:
        raise ApplyError("managed path is unsafe") from None
    if stat.S_ISREG(info.st_mode):
        return "file"
    if stat.S_ISDIR(info.st_mode):
        return "dir"
    if stat.S_ISLNK(info.st_mode):
        return "symlink"
    raise ApplyError("managed path is unsafe")


def _identity(path: Path, kind: str) -> list[Any]:
    info = path.lstat()
    return [info.st_dev, info.st_ino, kind]


def _publish_backup(path: Path, backup: Path, original: str) -> None:
    temporary: Path | None = None
    try:
        if original == "dir":
            temporary = Path(tempfile.mkdtemp(prefix=f".{backup.name}.", dir=backup.parent))
            _copy_directory(path, temporary)
        else:
            descriptor, name = tempfile.mkstemp(prefix=f".{backup.name}.", dir=backup.parent)
            temporary = Path(name)
            os.close(descriptor)
            if original == "absent":
                temporary.write_bytes(b"absent\n")
                _fsync_file(temporary)
            elif original == "file":
                _copy_file(path, temporary)
            elif original == "symlink":
                temporary.unlink()
                os.symlink(os.readlink(path), temporary)
                _copy_ownership(path, temporary, follow_symlinks=False)
                _fsync_directory(temporary.parent)
            else:
                raise ValueError
        os.replace(temporary, backup)
        temporary = None
        _fsync_directory(backup.parent)
        _failpoint("backup-published")
    finally:
        if temporary is not None:
            _safe_remove(temporary)


def _copy_file(source: Path, destination: Path) -> None:
    info = source.lstat()
    if not stat.S_ISREG(info.st_mode):
        raise ValueError
    with source.open("rb") as input_stream, destination.open("wb") as output_stream:
        shutil.copyfileobj(input_stream, output_stream)
        output_stream.flush()
        os.fsync(output_stream.fileno())
    os.chmod(destination, stat.S_IMODE(info.st_mode))
    _copy_ownership(source, destination)
    _fsync_file(destination)


def _copy_directory(
    source: Path,
    destination: Path,
    hardlinks: dict[tuple[int, int], Path] | None = None,
) -> None:
    info = source.lstat()
    if not stat.S_ISDIR(info.st_mode) or stat.S_ISLNK(info.st_mode):
        raise ValueError
    if hardlinks is None:
        hardlinks = {}
    with os.scandir(source) as entries:
        for entry in entries:
            child_source = Path(entry.path)
            child_destination = destination / entry.name
            kind = _entry_kind(child_source)
            if kind == "file":
                child_info = child_source.lstat()
                identity = (child_info.st_dev, child_info.st_ino)
                linked = hardlinks.get(identity)
                if linked is None:
                    descriptor = os.open(child_destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                    os.close(descriptor)
                    _copy_file(child_source, child_destination)
                    hardlinks[identity] = child_destination
                else:
                    os.link(linked, child_destination, follow_symlinks=False)
            elif kind == "dir":
                child_destination.mkdir(mode=0o700)
                _copy_directory(child_source, child_destination, hardlinks)
            elif kind == "symlink":
                os.symlink(os.readlink(child_source), child_destination)
                _copy_ownership(child_source, child_destination, follow_symlinks=False)
            else:
                raise ValueError
    os.chmod(destination, stat.S_IMODE(info.st_mode))
    _copy_ownership(source, destination)
    _fsync_directory(destination)


def _copy_ownership(source: Path, destination: Path, *, follow_symlinks: bool = True) -> None:
    info = source.stat(follow_symlinks=follow_symlinks)
    try:
        os.chown(destination, info.st_uid, info.st_gid, follow_symlinks=follow_symlinks)
    except (NotImplementedError, PermissionError, OSError):
        pass


def _restore_snapshot(data_root: Path, target: Path, backup: Path, original: str) -> None:
    if original == "absent":
        parent = _open_managed_parent(data_root, target)
        try:
            _verify_managed_parent(data_root, target, parent)
            if _lexists_at(parent, target.name):
                _verify_managed_parent(data_root, target, parent)
                _remove_safe_at(parent, target.name)
                os.fsync(parent)
                _verify_managed_parent(data_root, target, parent)
                _fsync_directory(target.parent)
        finally:
            _safe_close(parent)
        _failpoint("restore")
        return
    _validate_backup(backup, original)
    _replace_from_backup(data_root, backup, target, original)
    _failpoint("restore")


def _replace_from_backup(data_root: Path, backup: Path, target: Path, original: str) -> None:
    parent = _open_managed_parent(data_root, target)
    temporary: str | None = None
    retired: str | None = None
    try:
        _verify_managed_parent(data_root, target, parent)
        temporary = _temporary_sibling_at(parent, target.name, original == "dir")
        temporary_path = _descriptor_child(parent, temporary)
        if original == "file":
            _copy_file(backup, temporary_path)
        elif original == "dir":
            _copy_directory(backup, temporary_path)
        elif original == "symlink":
            _remove_safe_at(parent, temporary)
            os.symlink(os.readlink(backup), temporary, dir_fd=parent)
            _copy_ownership(backup, temporary_path, follow_symlinks=False)
        else:
            raise ValueError
        _verify_managed_parent(data_root, target, parent)
        if _lexists_at(parent, target.name):
            target_kind = _entry_kind_at(parent, target.name)
            retired = _temporary_sibling_at(parent, target.name, target_kind == "dir")
            _remove_safe_at(parent, retired)
            _verify_managed_parent(data_root, target, parent)
            os.replace(target.name, retired, src_dir_fd=parent, dst_dir_fd=parent)
            os.fsync(parent)
            _verify_managed_parent(data_root, target, parent)
        _verify_managed_parent(data_root, target, parent)
        os.replace(temporary, target.name, src_dir_fd=parent, dst_dir_fd=parent)
        temporary = None
        os.fsync(parent)
        _verify_managed_parent(data_root, target, parent)
        _fsync_directory(target.parent)
    finally:
        if temporary is not None:
            _remove_safe_at(parent, temporary)
        if retired is not None:
            _remove_safe_at(parent, retired)
        _safe_close(parent)


def _reverse_move(
    data_root: Path,
    transaction_directory: Path,
    entry_index: int,
    entry: dict[str, Any],
) -> None:
    source = data_root / entry["source"]
    target = data_root / entry["target"]
    source_quarantine, target_quarantine = _move_quarantine_names(entry_index)
    expected_link = os.path.relpath(target, source.parent)
    source_parent = _open_managed_parent(data_root, source)
    target_parent: int | None = None
    transaction_parent: int | None = None
    try:
        # Deterministic private names make every atomic rename state recoverable
        # without extending the version 1 journal schema.
        target_parent = _open_managed_parent(data_root, target)
        transaction_parent = _open_real_directory(transaction_directory)
        _verify_managed_parent(data_root, source, source_parent)
        _verify_managed_parent(data_root, target, target_parent)
        _verify_real_directory(transaction_directory, transaction_parent)
        source_kind = _entry_kind_at(source_parent, source.name)
        target_kind = _entry_kind_at(target_parent, target.name)
        source_quarantine_kind = _entry_kind_at(transaction_parent, source_quarantine)
        target_quarantine_kind = _entry_kind_at(transaction_parent, target_quarantine)

        if source_quarantine_kind != "absent" and not _exact_move_link(
            transaction_parent, source_quarantine, expected_link
        ):
            _restore_quarantine_if_possible(
                transaction_parent,
                source_quarantine,
                source_parent,
                source.name,
            )
            raise ValueError

        if target_quarantine_kind == "absent":
            if source_kind != "absent" and _identity_at(source_parent, source.name, source_kind) == entry["identity"]:
                if target_kind != "absent":
                    raise ValueError
                if source_quarantine_kind == "absent":
                    return
                if not _exact_move_link(transaction_parent, source_quarantine, expected_link):
                    raise ValueError
                return
            if source_quarantine_kind != "absent" and source_kind != "absent":
                raise ValueError
            if source_quarantine_kind == "absent" and source_kind == "symlink":
                source_identity = _identity_at(source_parent, source.name, source_kind)
                _failpoint("move-source-before-quarantine")
                _rename_noreplace(
                    source_parent,
                    source.name,
                    transaction_parent,
                    source_quarantine,
                )
                _sync_rename(source_parent, transaction_parent)
                _verify_managed_parent(data_root, source, source_parent)
                _verify_real_directory(transaction_directory, transaction_parent)
                if (
                    _entry_kind_at(transaction_parent, source_quarantine) != "symlink"
                    or _identity_at(transaction_parent, source_quarantine, "symlink") != source_identity
                    or _readlink_at(transaction_parent, source_quarantine) != expected_link
                ):
                    _restore_quarantine_if_possible(
                        transaction_parent,
                        source_quarantine,
                        source_parent,
                        source.name,
                    )
                    raise ValueError
                source_kind = _entry_kind_at(source_parent, source.name)
                source_quarantine_kind = "symlink"
                _failpoint("move-source-quarantined")
            elif source_kind != "absent":
                raise ValueError

            if source_kind != "absent":
                raise ValueError
            target_kind = _entry_kind_at(target_parent, target.name)
            if target_kind == "absent":
                raise ValueError
            _failpoint("move-target-before-quarantine")
            _rename_noreplace(
                target_parent,
                target.name,
                transaction_parent,
                target_quarantine,
            )
            _sync_rename(target_parent, transaction_parent)
            _verify_managed_parent(data_root, target, target_parent)
            _verify_real_directory(transaction_directory, transaction_parent)
            target_quarantine_kind = _entry_kind_at(transaction_parent, target_quarantine)
            if (
                target_quarantine_kind == "absent"
                or _identity_at(transaction_parent, target_quarantine, target_quarantine_kind)
                != entry["identity"]
            ):
                _restore_quarantine_if_possible(
                    transaction_parent,
                    target_quarantine,
                    target_parent,
                    target.name,
                )
                raise ValueError
            _failpoint("move-target-quarantined")

        if (
            target_quarantine_kind == "absent"
            or _identity_at(transaction_parent, target_quarantine, target_quarantine_kind)
            != entry["identity"]
        ):
            if target_quarantine_kind != "absent":
                _restore_quarantine_if_possible(
                    transaction_parent,
                    target_quarantine,
                    target_parent,
                    target.name,
                )
            raise ValueError
        source_kind = _entry_kind_at(source_parent, source.name)
        target_kind = _entry_kind_at(target_parent, target.name)
        if source_kind != "absent" or target_kind != "absent":
            raise ValueError

        _failpoint("move-target-before-restore")
        _rename_noreplace(
            transaction_parent,
            target_quarantine,
            source_parent,
            source.name,
        )
        _sync_rename(transaction_parent, source_parent)
        _verify_real_directory(transaction_directory, transaction_parent)
        _verify_managed_parent(data_root, source, source_parent)
        _verify_managed_parent(data_root, target, target_parent)
        source_kind = _entry_kind_at(source_parent, source.name)
        if (
            source_kind == "absent"
            or _identity_at(source_parent, source.name, source_kind) != entry["identity"]
            or _entry_kind_at(target_parent, target.name) != "absent"
            or _entry_kind_at(transaction_parent, target_quarantine) != "absent"
        ):
            raise ValueError
        _fsync_directory(source.parent)
        if target.parent != source.parent:
            _fsync_directory(target.parent)
        _failpoint("move-target-restored")
        _failpoint("restore")
    finally:
        if transaction_parent is not None:
            _safe_close(transaction_parent)
        if target_parent is not None:
            _safe_close(target_parent)
        _safe_close(source_parent)


def _move_quarantine_names(entry_index: int) -> tuple[str, str]:
    return (
        f"move-{entry_index:06d}-source-link",
        f"move-{entry_index:06d}-target-object",
    )


def _exact_move_link(parent: int, name: str, expected_link: str) -> bool:
    return _entry_kind_at(parent, name) == "symlink" and _readlink_at(parent, name) == expected_link


def _rename_noreplace(source_parent: int, source: str, target_parent: int, target: str) -> None:
    if _renameat2 is None:
        raise OSError(errno.ENOSYS, "atomic no-replace rename is unavailable")
    ctypes.set_errno(0)
    result = _renameat2(
        source_parent,
        os.fsencode(source),
        target_parent,
        os.fsencode(target),
        _RENAME_NOREPLACE,
    )
    if result == 0:
        return
    error = ctypes.get_errno()
    if error == errno.EEXIST:
        raise FileExistsError(error, "atomic no-replace destination exists")
    if error == errno.ENOENT:
        raise FileNotFoundError(error, "atomic no-replace source is absent")
    raise OSError(error, "atomic no-replace rename failed")


def _sync_rename(source_parent: int, target_parent: int) -> None:
    os.fsync(source_parent)
    if target_parent != source_parent:
        os.fsync(target_parent)


def _restore_quarantine_if_possible(
    quarantine_parent: int,
    quarantine: str,
    endpoint_parent: int,
    endpoint: str,
) -> None:
    try:
        _rename_noreplace(quarantine_parent, quarantine, endpoint_parent, endpoint)
        _sync_rename(quarantine_parent, endpoint_parent)
    except Exception:
        return


def _read_journal(directory: Path) -> dict[str, Any]:
    try:
        _require_directory(directory)
        journal_path = directory / _JOURNAL_NAME
        info = journal_path.lstat()
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
            raise ValueError
        loaded = json.loads(journal_path.read_bytes().decode("utf-8"))
        if not isinstance(loaded, dict):
            raise ValueError
        return loaded
    except Exception:
        raise ApplyError("bootstrap transaction journal is invalid") from None


def _validate_journal(data_root: Path, directory: Path, journal: dict[str, Any]) -> None:
    try:
        if set(journal) != {"version", "status", "entries"} or journal["version"] != _VERSION:
            raise ValueError
        if journal["status"] not in {"active", "rolling_back", "committed", "rolled_back"} or not isinstance(journal["entries"], list):
            raise ValueError
        snapshots: list[str] = []
        moves: set[str] = set()
        backups: set[str] = set()
        quarantines: dict[str, str] = {}
        for index, entry in enumerate(journal["entries"]):
            if not isinstance(entry, dict) or entry.get("state") not in {"preparing", "ready", "restored"}:
                raise ValueError
            if entry.get("kind") == "snapshot":
                if set(entry) != {"kind", "path", "state", "original", "backup"}:
                    raise ValueError
                relative = _validate_relative(entry["path"])
                if entry["original"] not in {"absent", "file", "dir", "symlink"} or entry["backup"] != f"backup-{index:06d}":
                    raise ValueError
                _validate_journal_managed_path(relative)
                if entry["state"] != "preparing" and any(_overlaps(relative, endpoint) for endpoint in moves):
                    raise ValueError
                if any(relative == known or _is_descendant(relative, known) for known in snapshots):
                    raise ValueError
                if any(_is_descendant(known, relative) for known in snapshots):
                    raise ValueError
                snapshots.append(relative)
                backups.add(entry["backup"])
                if journal["status"] in {"active", "rolling_back"} and entry["state"] in {"ready", "restored"}:
                    _validate_backup(directory / entry["backup"], entry["original"])
            elif entry.get("kind") == "move":
                if set(entry) != {"kind", "source", "target", "state", "identity"}:
                    raise ValueError
                source = _validate_relative(entry["source"])
                target = _validate_relative(entry["target"])
                if _overlaps(source, target) or source in moves or target in moves or not _valid_identity(entry["identity"]):
                    raise ValueError
                _validate_journal_managed_path(source)
                _validate_journal_managed_path(target)
                moves.update((source, target))
                source_quarantine, target_quarantine = _move_quarantine_names(index)
                quarantines[source_quarantine] = "source"
                quarantines[target_quarantine] = "target"
            else:
                raise ValueError
        _validate_entry_states(journal["status"], journal["entries"])
        _validate_journal_storage(directory, backups, quarantines, journal["status"])
    except ApplyError:
        raise ApplyError("bootstrap transaction journal is invalid") from None
    except Exception:
        raise ApplyError("bootstrap transaction journal is invalid") from None


def _validate_journal_storage(
    directory: Path,
    backups: set[str],
    quarantines: dict[str, str],
    status: str,
) -> None:
    with os.scandir(directory) as entries:
        for entry in entries:
            if entry.name == _JOURNAL_NAME:
                if not entry.is_file(follow_symlinks=False):
                    raise ValueError
            elif entry.name in backups:
                if entry.is_symlink():
                    raise ValueError
            elif entry.name.startswith(".journal-"):
                if not entry.is_file(follow_symlinks=False):
                    raise ValueError
            elif entry.name in quarantines:
                role = quarantines[entry.name]
                if status != "rolling_back" and not (status == "rolled_back" and role == "source"):
                    raise ValueError
                kind = _entry_kind(Path(entry.path))
                if role == "source" and kind != "symlink":
                    raise ValueError
            else:
                raise ValueError


def _validate_entry_states(status: str, entries: list[dict[str, Any]]) -> None:
    states = [entry["state"] for entry in entries]
    has_trailing_preparing = states[-1:] == ["preparing"]
    completed_states = states[:-1] if has_trailing_preparing else states
    if any(state == "preparing" for state in completed_states):
        raise ValueError
    if status == "active":
        if any(state != "ready" for state in completed_states):
            raise ValueError
        return
    if status == "rolling_back":
        restored = False
        for state in completed_states:
            if state == "restored":
                restored = True
            elif state != "ready" or restored:
                raise ValueError
        return
    if status == "committed":
        if has_trailing_preparing or any(state != "ready" for state in completed_states):
            raise ValueError
        return
    if status == "rolled_back":
        if any(state != "restored" for state in completed_states):
            raise ValueError
        return
    raise ValueError


def _validate_relative(value: object) -> str:
    if not isinstance(value, str) or not value or "\\" in value:
        raise ValueError
    path = Path(value)
    if path.is_absolute() or any(part in {"", ".", ".."} for part in path.parts):
        raise ValueError
    return path.as_posix()


def _validate_journal_managed_path(relative: str) -> None:
    if Path(relative).parts[:2] == (".bootstrap", "transactions"):
        raise ValueError


def _open_real_directory(path: Path) -> int:
    descriptor: int | None = None
    try:
        flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | os.O_CLOEXEC
        descriptor = os.open(path, flags | getattr(os, "O_NOFOLLOW", 0))
        info = path.lstat()
        opened = os.fstat(descriptor)
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(opened.st_mode):
            raise ValueError
        if (info.st_dev, info.st_ino) != (opened.st_dev, opened.st_ino):
            raise ValueError
        result = descriptor
        descriptor = None
        return result
    except Exception:
        raise ApplyError("managed path is unsafe") from None
    finally:
        if descriptor is not None:
            _safe_close(descriptor)


def _verify_real_directory(path: Path, descriptor: int) -> None:
    current = _open_real_directory(path)
    try:
        expected = os.fstat(descriptor)
        actual = os.fstat(current)
        if (expected.st_dev, expected.st_ino) != (actual.st_dev, actual.st_ino):
            raise ApplyError("managed path is unsafe")
    finally:
        _safe_close(current)


def _managed_path_is_absent(data_root: Path, path: Path) -> bool:
    descriptor: int | None = None
    try:
        relative = path.relative_to(data_root)
        if not relative.parts or any(part in {"", ".", ".."} for part in relative.parts):
            raise ValueError
        flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | os.O_CLOEXEC
        nofollow = getattr(os, "O_NOFOLLOW", 0)
        descriptor = os.open(data_root, flags | nofollow)
        root_info = data_root.lstat()
        opened = os.fstat(descriptor)
        if not stat.S_ISDIR(opened.st_mode) or (root_info.st_dev, root_info.st_ino) != (
            opened.st_dev,
            opened.st_ino,
        ):
            raise ValueError
        current = data_root
        for part in relative.parts[:-1]:
            try:
                child = os.open(part, flags | nofollow, dir_fd=descriptor)
            except FileNotFoundError:
                _verify_real_directory(current, descriptor)
                if _lexists_at(descriptor, part):
                    raise ValueError
                return True
            try:
                child_path_info = os.stat(part, dir_fd=descriptor, follow_symlinks=False)
                child_info = os.fstat(child)
                if (
                    not stat.S_ISDIR(child_info.st_mode)
                    or stat.S_ISLNK(child_path_info.st_mode)
                    or (child_path_info.st_dev, child_path_info.st_ino)
                    != (child_info.st_dev, child_info.st_ino)
                ):
                    raise ValueError
            except Exception:
                os.close(child)
                raise
            os.close(descriptor)
            descriptor = child
            current /= part
        _verify_real_directory(current, descriptor)
        return _entry_kind_at(descriptor, path.name) == "absent"
    except ApplyError:
        raise
    except Exception:
        raise ApplyError("managed path is unsafe") from None
    finally:
        if descriptor is not None:
            _safe_close(descriptor)


def _open_managed_parent(data_root: Path, path: Path) -> int:
    descriptor: int | None = None
    try:
        relative = path.relative_to(data_root)
        if not relative.parts or any(part in {"", ".", ".."} for part in relative.parts):
            raise ValueError
        flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | os.O_CLOEXEC
        nofollow = getattr(os, "O_NOFOLLOW", 0)
        descriptor = os.open(data_root, flags | nofollow)
        root_info = data_root.lstat()
        opened = os.fstat(descriptor)
        if not stat.S_ISDIR(opened.st_mode) or (root_info.st_dev, root_info.st_ino) != (opened.st_dev, opened.st_ino):
            raise ValueError
        for part in relative.parts[:-1]:
            child = os.open(part, flags | nofollow, dir_fd=descriptor)
            child_path_info = os.stat(part, dir_fd=descriptor, follow_symlinks=False)
            child_info = os.fstat(child)
            if (
                not stat.S_ISDIR(child_info.st_mode)
                or stat.S_ISLNK(child_path_info.st_mode)
                or (child_path_info.st_dev, child_path_info.st_ino) != (child_info.st_dev, child_info.st_ino)
            ):
                os.close(child)
                raise ValueError
            os.close(descriptor)
            descriptor = child
        result = descriptor
        descriptor = None
        return result
    except Exception:
        raise ApplyError("managed path is unsafe") from None
    finally:
        if descriptor is not None:
            _safe_close(descriptor)


def _verify_managed_parent(data_root: Path, path: Path, descriptor: int) -> None:
    current = _open_managed_parent(data_root, path)
    try:
        expected = os.fstat(descriptor)
        actual = os.fstat(current)
        if (expected.st_dev, expected.st_ino) != (actual.st_dev, actual.st_ino):
            raise ApplyError("managed path is unsafe")
    finally:
        _safe_close(current)


def _entry_kind_at(parent: int, name: str) -> str:
    try:
        info = os.stat(name, dir_fd=parent, follow_symlinks=False)
    except FileNotFoundError:
        return "absent"
    except OSError:
        raise ApplyError("managed path is unsafe") from None
    if stat.S_ISREG(info.st_mode):
        return "file"
    if stat.S_ISDIR(info.st_mode):
        return "dir"
    if stat.S_ISLNK(info.st_mode):
        return "symlink"
    raise ApplyError("managed path is unsafe")


def _readlink_at(parent: int, name: str) -> str:
    try:
        return os.readlink(name, dir_fd=parent)
    except OSError:
        raise ApplyError("managed path is unsafe") from None


def _identity_at(parent: int, name: str, kind: str) -> list[Any]:
    info = os.stat(name, dir_fd=parent, follow_symlinks=False)
    return [info.st_dev, info.st_ino, kind]


def _valid_identity(value: object) -> bool:
    return (
        isinstance(value, list)
        and len(value) == 3
        and type(value[0]) is int
        and type(value[1]) is int
        and value[0] >= 0
        and value[1] >= 0
        and value[2] in {"file", "dir", "symlink"}
    )


def _validate_backup(backup: Path, original: str) -> None:
    if _BACKUP_ID.fullmatch(backup.name) is None or not backup.parent.is_dir() or backup.parent.is_symlink():
        raise ValueError
    kind = _entry_kind(backup)
    if original == "absent":
        if kind != "file":
            raise ValueError
    elif kind != original:
        raise ValueError
    if kind == "dir":
        _validate_backup_tree(backup)
    elif kind == "file" and backup.lstat().st_nlink != 1:
        raise ValueError


def _validate_backup_tree(path: Path) -> None:
    links: dict[tuple[int, int], tuple[int, int]] = {}
    _collect_backup_links(path, links)
    if any(count != link_count for count, link_count in links.values()):
        raise ValueError


def _collect_backup_links(path: Path, links: dict[tuple[int, int], tuple[int, int]]) -> None:
    with os.scandir(path) as entries:
        for entry in entries:
            child = Path(entry.path)
            kind = _entry_kind(child)
            if kind == "dir":
                _collect_backup_links(child, links)
            elif kind == "file":
                info = child.lstat()
                identity = (info.st_dev, info.st_ino)
                count, link_count = links.get(identity, (0, info.st_nlink))
                if link_count != info.st_nlink:
                    raise ValueError
                links[identity] = (count + 1, link_count)
            elif kind != "symlink":
                raise ValueError


def _atomic_write_json(path: Path, payload: dict[str, Any]) -> None:
    temporary: Path | None = None
    try:
        encoded = (json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
        descriptor, name = tempfile.mkstemp(prefix=".journal-", dir=path.parent)
        temporary = Path(name)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(encoded)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
        temporary = None
        _fsync_directory(path.parent)
    finally:
        if temporary is not None:
            _safe_remove(temporary)


def _cleanup_transaction(
    data_root: Path,
    directory: Path,
    store: Path,
    journal: dict[str, Any],
) -> None:
    _require_directory(directory)
    quarantines: dict[str, tuple[str, int, dict[str, Any]]] = {}
    for index, entry in enumerate(journal["entries"]):
        if entry["kind"] != "move":
            continue
        source_quarantine, target_quarantine = _move_quarantine_names(index)
        quarantines[source_quarantine] = ("source", index, entry)
        quarantines[target_quarantine] = ("target", index, entry)
    with os.scandir(directory) as entries:
        names = [entry.name for entry in entries]
    transaction_parent = _open_real_directory(directory)
    try:
        for name in sorted(names):
            if _BACKUP_ID.fullmatch(name):
                _remove_safe(directory / name)
                _fsync_directory(directory)
                _cleanup_failpoint("cleanup-backup")
            elif name.startswith(".journal-"):
                _remove_safe(directory / name)
                _fsync_directory(directory)
                _cleanup_failpoint("cleanup-temp")
            elif name in quarantines:
                role, entry_index, entry = quarantines[name]
                if journal["status"] != "rolled_back" or role != "source":
                    raise ValueError
                quarantine_identity = _verify_move_cleanup_state(
                    data_root,
                    directory,
                    transaction_parent,
                    entry_index,
                    entry,
                    require_source_quarantine=True,
                )
                assert quarantine_identity is not None
                _failpoint("cleanup-quarantine-before-unlink")
                _verify_move_cleanup_state(
                    data_root,
                    directory,
                    transaction_parent,
                    entry_index,
                    entry,
                    require_source_quarantine=True,
                    source_quarantine_identity=quarantine_identity,
                )
                # This mode-0700 directory is the trust boundary for the final
                # private unlink; managed endpoint changes use RENAME_NOREPLACE.
                os.unlink(name, dir_fd=transaction_parent)
                os.fsync(transaction_parent)
                _cleanup_failpoint("cleanup-quarantine")
            elif name != _JOURNAL_NAME:
                raise ValueError
    finally:
        _safe_close(transaction_parent)
    transaction_parent = _open_real_directory(directory)
    try:
        if journal["status"] == "rolled_back":
            for entry_index, entry in enumerate(journal["entries"]):
                if (
                    entry["kind"] == "move"
                    and entry["state"] == "restored"
                    and _requires_exact_move_cleanup(journal["entries"], entry_index, entry)
                ):
                    _verify_move_cleanup_state(
                        data_root,
                        directory,
                        transaction_parent,
                        entry_index,
                        entry,
                        require_source_quarantine=False,
                    )
        _verify_real_directory(directory, transaction_parent)
        if _lexists_at(transaction_parent, _JOURNAL_NAME):
            if _entry_kind_at(transaction_parent, _JOURNAL_NAME) != "file":
                raise ValueError
            os.unlink(_JOURNAL_NAME, dir_fd=transaction_parent)
            os.fsync(transaction_parent)
            _cleanup_failpoint("cleanup-journal")
    finally:
        _safe_close(transaction_parent)
    directory.rmdir()
    _fsync_directory(store)
    _cleanup_failpoint("cleanup-directory")


def _verify_move_cleanup_state(
    data_root: Path,
    transaction_directory: Path,
    transaction_parent: int,
    entry_index: int,
    entry: dict[str, Any],
    *,
    require_source_quarantine: bool,
    source_quarantine_identity: list[Any] | None = None,
) -> list[Any] | None:
    source = data_root / entry["source"]
    target = data_root / entry["target"]
    source_quarantine, target_quarantine = _move_quarantine_names(entry_index)
    expected_link = os.path.relpath(target, source.parent)
    source_parent = _open_managed_parent(data_root, source)
    target_parent: int | None = None
    try:
        try:
            target_parent = _open_managed_parent(data_root, target)
        except ApplyError:
            if not _managed_path_is_absent(data_root, target):
                raise
        _verify_real_directory(transaction_directory, transaction_parent)
        _verify_managed_parent(data_root, source, source_parent)
        if target_parent is not None:
            _verify_managed_parent(data_root, target, target_parent)
        source_kind = _entry_kind_at(source_parent, source.name)
        if source_kind == "absent" or _identity_at(source_parent, source.name, source_kind) != entry["identity"]:
            raise ValueError
        if target_parent is not None and _entry_kind_at(target_parent, target.name) != "absent":
            raise ValueError
        if _entry_kind_at(transaction_parent, target_quarantine) != "absent":
            raise ValueError
        source_quarantine_kind = _entry_kind_at(transaction_parent, source_quarantine)
        if require_source_quarantine:
            if source_quarantine_kind != "symlink" or _readlink_at(
                transaction_parent, source_quarantine
            ) != expected_link:
                raise ValueError
            current_identity = _identity_at(transaction_parent, source_quarantine, "symlink")
            if source_quarantine_identity is not None and current_identity != source_quarantine_identity:
                raise ValueError
            return current_identity
        if source_quarantine_kind != "absent":
            raise ValueError
        return None
    finally:
        if target_parent is not None:
            _safe_close(target_parent)
        _safe_close(source_parent)


def _requires_exact_move_cleanup(
    entries: list[dict[str, Any]],
    entry_index: int,
    move: dict[str, Any],
) -> bool:
    preceding = entries[:entry_index]
    source = move["source"]
    target = move["target"]
    if any(
        entry["kind"] == "snapshot"
        and (entry["path"] == source or _is_descendant(source, entry["path"]))
        for entry in preceding
    ):
        return False
    target_snapshots = [
        entry
        for entry in preceding
        if entry["kind"] == "snapshot"
        and (entry["path"] == target or _is_descendant(target, entry["path"]))
    ]
    if not target_snapshots:
        return True
    return len(target_snapshots) == 1 and target_snapshots[0]["original"] == "absent"


def _cleanup_failpoint(name: str) -> None:
    _failpoint("cleanup-step")
    _failpoint(name)


def _remove_empty_transaction(directory: Path, store: Path) -> None:
    _require_directory(directory)
    with os.scandir(directory) as entries:
        if next(entries, None) is not None:
            raise ApplyError("bootstrap transaction journal is invalid")
    directory.rmdir()
    _fsync_directory(store)


def _safe_remove_empty_initial_transaction(directory: Path | None, store: Path) -> None:
    if directory is None:
        return
    try:
        _remove_empty_transaction(directory, store)
    except Exception:
        pass


def _temporary_sibling_at(parent: int, basename: str, directory: bool) -> str:
    while True:
        name = f".{basename}.bootstrap-{uuid.uuid4()}"
        try:
            if directory:
                os.mkdir(name, mode=0o700, dir_fd=parent)
            else:
                descriptor = os.open(
                    name,
                    os.O_RDWR | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC | getattr(os, "O_NOFOLLOW", 0),
                    0o600,
                    dir_fd=parent,
                )
                os.close(descriptor)
            return name
        except FileExistsError:
            continue


def _descriptor_child(descriptor: int, name: str) -> Path:
    base = Path("/proc/self/fd")
    if not base.is_dir():
        base = Path("/dev/fd")
    return base / str(descriptor) / name


def _lexists_at(parent: int, name: str) -> bool:
    try:
        os.stat(name, dir_fd=parent, follow_symlinks=False)
    except FileNotFoundError:
        return False
    return True


def _remove_safe_at(parent: int, name: str) -> None:
    kind = _entry_kind_at(parent, name)
    if kind == "absent":
        return
    if kind == "dir":
        shutil.rmtree(name, dir_fd=parent)
    else:
        os.unlink(name, dir_fd=parent)


def _remove_safe(path: Path) -> None:
    kind = _entry_kind(path)
    if kind == "absent":
        return
    if kind == "dir":
        shutil.rmtree(path)
    else:
        path.unlink()


def _require_directory(path: Path) -> None:
    info = path.lstat()
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
        raise ValueError


def _fsync_file(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY | os.O_CLOEXEC)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _fsync_directory(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | os.O_CLOEXEC)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _lexists(path: Path) -> bool:
    try:
        path.lstat()
    except FileNotFoundError:
        return False
    return True


def _safe_remove(path: Path) -> None:
    try:
        _remove_safe(path)
    except Exception:
        pass


def _safe_close(descriptor: int) -> None:
    try:
        os.close(descriptor)
    except OSError:
        pass


def _is_descendant(candidate: str, parent: str) -> bool:
    return candidate.startswith(parent + "/")


def _overlaps(first: str, second: str) -> bool:
    return first == second or _is_descendant(first, second) or _is_descendant(second, first)


def _entry_paths(entry: dict[str, Any]) -> list[str]:
    if entry["kind"] == "snapshot":
        return [entry["path"]]
    return [entry["source"], entry["target"]]
