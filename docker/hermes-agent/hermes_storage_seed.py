#!/usr/bin/env python3
"""Seed a fresh Hermes Docker volume from a stopped host data directory."""

from __future__ import annotations

import argparse
import os
import shutil
import sqlite3
import stat
from pathlib import Path


TRANSIENT_SQLITE_SUFFIXES = ("-wal", "-shm", "-journal")
EXCLUDED_ROOT_ENTRIES = {".browser", ".op.env", ".xurl"}


def _is_sqlite_database(path: Path) -> bool:
    try:
        with path.open("rb") as handle:
            return handle.read(16) == b"SQLite format 3\x00"
    except OSError:
        return False


def _copy_sqlite_database(source: Path, destination: Path) -> None:
    source_uri = f"file:{source.as_posix()}?mode=ro"
    source_connection = sqlite3.connect(source_uri, uri=True)
    destination_connection = sqlite3.connect(destination)
    try:
        source_connection.backup(destination_connection)
    finally:
        destination_connection.close()
        source_connection.close()


def _copy_file(source: Path, destination: Path) -> None:
    source_mode = stat.S_IMODE(source.stat().st_mode)
    shutil.copy2(source, destination)
    destination.chmod(source_mode)


def _validate_paths(source: Path, destination: Path) -> None:
    if not source.is_dir() or source.is_symlink():
        raise ValueError(f"source must be a real directory: {source}")
    if not destination.is_dir() or destination.is_symlink():
        raise ValueError(f"destination must be a real directory: {destination}")
    if any(destination.iterdir()):
        raise ValueError(f"destination must be empty: {destination}")


def seed(source: Path, destination: Path) -> None:
    """Copy a stopped Hermes home into an empty destination directory."""

    _validate_paths(source, destination)
    for source_root, directory_names, file_names in os.walk(source, followlinks=False):
        source_directory = Path(source_root)
        relative_directory = source_directory.relative_to(source)
        is_root = relative_directory == Path(".")
        destination_directory = destination / relative_directory
        destination_directory.mkdir(parents=True, exist_ok=True)

        retained_directories: list[str] = []
        for directory_name in directory_names:
            relative_path = relative_directory / directory_name
            if is_root and directory_name in EXCLUDED_ROOT_ENTRIES:
                continue
            source_path = source / relative_path
            if source_path.is_symlink():
                raise ValueError(f"symlinks are not supported in Hermes data: {source_path}")
            retained_directories.append(directory_name)
            (destination / relative_path).mkdir(exist_ok=True)
        directory_names[:] = retained_directories

        for file_name in file_names:
            if file_name.endswith(TRANSIENT_SQLITE_SUFFIXES):
                continue
            if is_root and file_name in EXCLUDED_ROOT_ENTRIES:
                continue
            relative_path = relative_directory / file_name
            source_path = source / relative_path
            if source_path.is_symlink():
                raise ValueError(f"symlinks are not supported in Hermes data: {source_path}")
            destination_path = destination / relative_path
            if source_path.suffix == ".db" and _is_sqlite_database(source_path):
                _copy_sqlite_database(source_path, destination_path)
                destination_path.chmod(stat.S_IMODE(source_path.stat().st_mode))
            else:
                _copy_file(source_path, destination_path)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--destination", type=Path, required=True)
    arguments = parser.parse_args()
    try:
        seed(arguments.source, arguments.destination)
    except (OSError, sqlite3.Error, ValueError) as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
