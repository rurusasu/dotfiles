#!/usr/bin/env python3
"""Seed a fresh Hermes Docker volume from a stopped host data directory."""

from __future__ import annotations

import argparse
import contextlib
import os
import re
import shutil
import sqlite3
import stat
import tempfile
from pathlib import Path
from typing import Iterator


TRANSIENT_SQLITE_SUFFIXES = ("-wal", "-shm", "-journal")
READY_MARKER_NAME = ".dotfiles-hermes-storage-ready-v1"
EXCLUDED_ROOT_ENTRIES = {
    ".browser",
    ".op.env",
    ".xurl",
    "gateway.sock",
    READY_MARKER_NAME,
}
EXCLUDED_DIRECTORY_NAMES = {".cache"}
EXCLUDED_RELATIVE_PATHS = {Path(".bootstrap/transactions")}
PRIVATE_RELATIVE_DIRECTORIES = {Path(".bootstrap")}
ALLOWED_ABSOLUTE_SYMLINK_ROOT = Path("/opt/data")
READY_TOKEN_PATTERN = re.compile(r"^[0-9a-f]{32}$")


def _is_sqlite_database(path: Path) -> bool:
    try:
        with path.open("rb") as handle:
            return handle.read(16) == b"SQLite format 3\x00"
    except OSError:
        return False


@contextlib.contextmanager
def _open_sqlite_source(source: Path) -> Iterator[sqlite3.Connection]:
    sidecars = [Path(f"{source}{suffix}") for suffix in TRANSIENT_SQLITE_SUFFIXES]
    existing_sidecars = [path for path in sidecars if path.exists()]
    if not existing_sidecars:
        source_uri = f"{source.resolve().as_uri()}?mode=ro&immutable=1"
        connection = sqlite3.connect(source_uri, uri=True)
        try:
            yield connection
        finally:
            connection.close()
        return

    with tempfile.TemporaryDirectory(prefix="hermes-storage-sqlite-") as temporary:
        staged = Path(temporary) / source.name
        shutil.copy2(source, staged)
        staged.chmod(0o600)
        for sidecar in existing_sidecars:
            staged_sidecar = Path(f"{staged}{sidecar.name.removeprefix(source.name)}")
            shutil.copy2(sidecar, staged_sidecar)
            staged_sidecar.chmod(0o600)
        connection = sqlite3.connect(staged)
        try:
            yield connection
        finally:
            connection.close()


def _copy_sqlite_database(source: Path, destination: Path) -> None:
    destination_connection = sqlite3.connect(destination)
    try:
        with _open_sqlite_source(source) as source_connection:
            source_connection.backup(destination_connection)
    finally:
        destination_connection.close()


def _copy_file(source: Path, destination: Path) -> None:
    source_mode = stat.S_IMODE(source.stat().st_mode)
    shutil.copy2(source, destination)
    destination.chmod(source_mode)


def _is_within(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
    except ValueError:
        return False
    return True


def _is_excluded_entry(relative_path: Path, *, is_root: bool) -> bool:
    return (
        relative_path in EXCLUDED_RELATIVE_PATHS
        or relative_path.name in EXCLUDED_DIRECTORY_NAMES
        or (is_root and relative_path.name in EXCLUDED_ROOT_ENTRIES)
    )


def _copy_symlink(source_root: Path, source: Path, destination: Path) -> None:
    target_text = os.readlink(source)
    target = Path(target_text)
    if target.is_absolute():
        normalized_target = Path(os.path.normpath(target))
        if not _is_within(normalized_target, ALLOWED_ABSOLUTE_SYMLINK_ROOT):
            raise ValueError(f"absolute symlink target must be below /opt/data: {source} -> {target_text}")
    else:
        relative_parent = source.parent.relative_to(source_root)
        relocated_target = Path(os.path.normpath(relative_parent / target))
        if relocated_target.parts and relocated_target.parts[0] == "..":
            raise ValueError(f"relative symlink target escapes Hermes data after relocation: {source} -> {target_text}")
        resolved_target = (source.parent / target).resolve(strict=False)
        if not _is_within(resolved_target, source_root.resolve()):
            raise ValueError(f"relative symlink target escapes Hermes data: {source} -> {target_text}")
    destination.symlink_to(target_text)


def _fsync_tree(root: Path) -> None:
    directories: list[Path] = []
    for directory, directory_names, file_names in os.walk(root, followlinks=False):
        current = Path(directory)
        directories.append(current)
        directory_names[:] = [name for name in directory_names if not (current / name).is_symlink()]
        for file_name in file_names:
            path = current / file_name
            if path.is_symlink():
                continue
            descriptor = os.open(path, os.O_RDONLY)
            try:
                os.fsync(descriptor)
            finally:
                os.close(descriptor)
    for directory in reversed(directories):
        descriptor = os.open(directory, os.O_RDONLY)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)


def _write_ready_marker(destination: Path, ready_token: str) -> None:
    temporary = destination / f"{READY_MARKER_NAME}.tmp-{os.getpid()}"
    with temporary.open("x", encoding="utf-8") as handle:
        handle.write(f"version=1\nvolume_token={ready_token}\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary, destination / READY_MARKER_NAME)
    descriptor = os.open(destination, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _validate_paths(source: Path, destination: Path, ready_token: str) -> None:
    if not READY_TOKEN_PATTERN.fullmatch(ready_token):
        raise ValueError("ready token must be 32 lowercase hexadecimal characters")
    if not source.is_dir() or source.is_symlink():
        raise ValueError(f"source must be a real directory: {source}")
    if not destination.is_dir() or destination.is_symlink():
        raise ValueError(f"destination must be a real directory: {destination}")


def _validate_source_transaction_state(source: Path) -> None:
    store = source / ".bootstrap" / "transactions"
    descriptor: int | None = None
    try:
        flags = os.O_RDONLY | os.O_CLOEXEC | getattr(os, "O_DIRECTORY", 0)
        flags |= getattr(os, "O_NOFOLLOW", 0)
        descriptor = os.open(store, flags)
        opened = os.fstat(descriptor)
        if not stat.S_ISDIR(opened.st_mode):
            raise OSError
        with os.scandir(descriptor) as entries:
            if any(entry.name != ".lock" for entry in entries):
                raise ValueError(
                    "source contains bootstrap transaction recovery state; "
                    "recover the source before seeding"
                )
    except FileNotFoundError:
        return
    except ValueError:
        raise
    except OSError:
        raise ValueError(f"source bootstrap transaction store is unsafe: {store}") from None
    finally:
        if descriptor is not None:
            os.close(descriptor)


def _clear_destination(destination: Path) -> None:
    for path in destination.iterdir():
        if path.is_dir() and not path.is_symlink():
            shutil.rmtree(path)
        else:
            path.unlink()


def seed(source: Path, destination: Path, ready_token: str, *, replace_incomplete: bool = False) -> None:
    """Copy a stopped Hermes home into a destination and publish readiness."""

    _validate_paths(source, destination, ready_token)
    _validate_source_transaction_state(source)
    if replace_incomplete:
        _clear_destination(destination)
    elif any(destination.iterdir()):
        raise ValueError(f"destination must be empty: {destination}")
    for source_root, directory_names, file_names in os.walk(source, followlinks=False):
        source_directory = Path(source_root)
        relative_directory = source_directory.relative_to(source)
        is_root = relative_directory == Path(".")
        destination_directory = destination / relative_directory
        destination_directory.mkdir(parents=True, exist_ok=True)
        if relative_directory in PRIVATE_RELATIVE_DIRECTORIES:
            destination_directory.chmod(0o700)

        retained_directories: list[str] = []
        for directory_name in directory_names:
            relative_path = relative_directory / directory_name
            if _is_excluded_entry(relative_path, is_root=is_root):
                continue
            source_path = source / relative_path
            if source_path.is_symlink():
                _copy_symlink(source, source_path, destination / relative_path)
                continue
            retained_directories.append(directory_name)
            (destination / relative_path).mkdir(exist_ok=True)
        directory_names[:] = retained_directories

        for file_name in file_names:
            if file_name.endswith(TRANSIENT_SQLITE_SUFFIXES):
                continue
            relative_path = relative_directory / file_name
            if _is_excluded_entry(relative_path, is_root=is_root):
                continue
            source_path = source / relative_path
            source_metadata = source_path.lstat()
            if stat.S_ISLNK(source_metadata.st_mode):
                _copy_symlink(source, source_path, destination / relative_path)
                continue
            if not stat.S_ISREG(source_metadata.st_mode):
                continue
            destination_path = destination / relative_path
            if source_path.suffix == ".db" and _is_sqlite_database(source_path):
                _copy_sqlite_database(source_path, destination_path)
                destination_path.chmod(stat.S_IMODE(source_path.stat().st_mode))
            else:
                _copy_file(source_path, destination_path)

    _fsync_tree(destination)
    _write_ready_marker(destination, ready_token)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--destination", type=Path, required=True)
    parser.add_argument("--ready-token", required=True)
    parser.add_argument("--replace-incomplete", action="store_true")
    arguments = parser.parse_args()
    try:
        seed(
            arguments.source,
            arguments.destination,
            arguments.ready_token,
            replace_incomplete=arguments.replace_incomplete,
        )
    except (OSError, sqlite3.Error, ValueError) as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
