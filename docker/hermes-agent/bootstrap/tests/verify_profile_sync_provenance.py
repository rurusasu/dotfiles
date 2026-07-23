#!/usr/bin/env python3
"""Verify the profile-sync fixture against clean, committed Git sources."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import NoReturn


FIXTURE_PATH = Path(
    "docker/hermes-agent/bootstrap/tests/fixtures/hermes-home/profile_sync.sh"
)
PROVENANCE_PATH = FIXTURE_PATH.with_name("profile_sync.provenance.json")
SOURCE_REPOSITORY = "rurusasu/hermes-home"
PROVENANCE_KEYS = frozenset(
    {
        "source_repository",
        "source_commit",
        "source_path",
        "git_blob_sha1",
        "sha256",
    }
)
SHA1_PATTERN = re.compile(r"[0-9a-f]{40}\Z")
SHA256_PATTERN = re.compile(r"[0-9a-f]{64}\Z")
SOURCE_PATH_PATTERN = re.compile(r"[A-Za-z0-9._/-]+\Z")
ERROR_PREFIX = "profile sync provenance verification failed"


class VerificationError(Exception):
    """A content-free, stable verification failure."""


class DuplicateKeyError(ValueError):
    """Raised when JSON contains a duplicate object key."""


@dataclass(frozen=True)
class Provenance:
    source_repository: str
    source_commit: str
    source_path: str
    git_blob_sha1: str
    sha256: str


@dataclass(frozen=True)
class TreeEntry:
    mode: str
    object_type: str
    object_id: str


def _fail(reason: str) -> NoReturn:
    raise VerificationError(reason)


def _same_path(left: Path, right: Path) -> bool:
    return os.path.normcase(str(left)) == os.path.normcase(str(right))


def _git(
    repository: Path,
    *arguments: str,
) -> subprocess.CompletedProcess[str]:
    environment = os.environ.copy()
    environment.update(
        {
            "GIT_OPTIONAL_LOCKS": "0",
            "LANG": "C",
            "LC_ALL": "C",
        }
    )
    try:
        return subprocess.run(
            ("git", "-C", str(repository), *arguments),
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
            timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        _fail("Git command could not be executed")


def _require_git_root(repository: Path, label: str) -> Path:
    try:
        candidate = repository.resolve(strict=True)
    except OSError:
        _fail(f"{label} repository is not a Git worktree root")
    if not candidate.is_dir():
        _fail(f"{label} repository is not a Git worktree root")

    result = _git(candidate, "rev-parse", "--show-toplevel")
    if result.returncode != 0:
        _fail(f"{label} repository is not a Git worktree root")
    try:
        top_level = Path(result.stdout.strip()).resolve(strict=True)
    except OSError:
        _fail(f"{label} repository is not a Git worktree root")
    if not _same_path(candidate, top_level):
        _fail(f"{label} repository is not a Git worktree root")
    return candidate


def _tree_entry(
    repository: Path,
    path: Path,
    label: str,
) -> TreeEntry:
    result = _git(
        repository,
        "-c",
        "core.quotepath=false",
        "ls-tree",
        "-z",
        "HEAD",
        "--",
        path.as_posix(),
    )
    if result.returncode != 0:
        _fail(f"{label} Git tree lookup failed")
    records = [record for record in result.stdout.split("\0") if record]
    if len(records) != 1:
        _fail(f"{label} is not tracked at HEAD")
    try:
        metadata, returned_path = records[0].split("\t", maxsplit=1)
        mode, object_type, object_id = metadata.split()
    except ValueError:
        _fail(f"{label} Git tree entry is malformed")
    if returned_path != path.as_posix() or object_type != "blob":
        _fail(f"{label} is not tracked at HEAD")
    if SHA1_PATTERN.fullmatch(object_id) is None:
        _fail(f"{label} Git blob ID is malformed")
    return TreeEntry(
        mode=mode,
        object_type=object_type,
        object_id=object_id,
    )


def _require_clean(
    repository: Path,
    path: Path,
    label: str,
) -> None:
    staged = _git(
        repository,
        "diff",
        "--cached",
        "--quiet",
        "--no-ext-diff",
        "HEAD",
        "--",
        path.as_posix(),
    )
    unstaged = _git(
        repository,
        "diff",
        "--quiet",
        "--no-ext-diff",
        "--",
        path.as_posix(),
    )
    if staged.returncode == 1 or unstaged.returncode == 1:
        _fail(f"{label} is dirty")
    if staged.returncode != 0 or unstaged.returncode != 0:
        _fail(f"{label} Git cleanliness check failed")


def _read_regular_file(path: Path, label: str) -> bytes:
    if path.is_symlink() or not path.is_file():
        _fail(f"{label} is not a regular file")
    try:
        return path.read_bytes()
    except OSError:
        _fail(f"{label} could not be read")


def _reject_duplicate_keys(
    pairs: list[tuple[str, object]],
) -> dict[str, object]:
    document: dict[str, object] = {}
    for key, value in pairs:
        if key in document:
            raise DuplicateKeyError
        document[key] = value
    return document


def _parse_provenance(document: bytes) -> Provenance:
    try:
        parsed = json.loads(
            document.decode("utf-8"),
            object_pairs_hook=_reject_duplicate_keys,
        )
    except DuplicateKeyError:
        _fail("provenance contains duplicate keys")
    except (UnicodeDecodeError, json.JSONDecodeError):
        _fail("provenance is not valid JSON")

    if type(parsed) is not dict:
        _fail("provenance must be a JSON object")
    if set(parsed) != PROVENANCE_KEYS:
        _fail("provenance keys do not match the schema")

    source_repository = parsed["source_repository"]
    if type(source_repository) is not str or source_repository != SOURCE_REPOSITORY:
        _fail("provenance source_repository is invalid")

    source_commit = parsed["source_commit"]
    if type(source_commit) is not str or SHA1_PATTERN.fullmatch(source_commit) is None:
        _fail("provenance source_commit is invalid")

    source_path = parsed["source_path"]
    if type(source_path) is not str or not _valid_source_path(source_path):
        _fail("provenance source_path is invalid")

    git_blob_sha1 = parsed["git_blob_sha1"]
    if type(git_blob_sha1) is not str or SHA1_PATTERN.fullmatch(git_blob_sha1) is None:
        _fail("provenance git_blob_sha1 is invalid")

    sha256 = parsed["sha256"]
    if type(sha256) is not str or SHA256_PATTERN.fullmatch(sha256) is None:
        _fail("provenance sha256 is invalid")

    return Provenance(
        source_repository=source_repository,
        source_commit=source_commit,
        source_path=source_path,
        git_blob_sha1=git_blob_sha1,
        sha256=sha256,
    )


def _valid_source_path(value: str) -> bool:
    if SOURCE_PATH_PATTERN.fullmatch(value) is None or "\\" in value:
        return False
    path = PurePosixPath(value)
    return (
        bool(path.parts)
        and not path.is_absolute()
        and value == path.as_posix()
        and all(part not in {"", ".", ".."} for part in path.parts)
    )


def _load_dotfiles_provenance(
    dotfiles_repository: Path,
) -> tuple[Path, Provenance, TreeEntry]:
    dotfiles = _require_git_root(dotfiles_repository, "dotfiles")
    provenance_entry = _tree_entry(
        dotfiles,
        PROVENANCE_PATH,
        "dotfiles provenance",
    )
    _require_clean(
        dotfiles,
        PROVENANCE_PATH,
        "dotfiles provenance",
    )
    document = _read_regular_file(
        dotfiles / PROVENANCE_PATH,
        "dotfiles provenance",
    )
    return dotfiles, _parse_provenance(document), provenance_entry


def read_source_commit(dotfiles_repository: Path) -> str:
    _, provenance, _ = _load_dotfiles_provenance(dotfiles_repository)
    return provenance.source_commit


def _head_commit(repository: Path, label: str) -> str:
    result = _git(repository, "rev-parse", "--verify", "HEAD^{commit}")
    commit = result.stdout.strip()
    if result.returncode != 0 or SHA1_PATTERN.fullmatch(commit) is None:
        _fail(f"{label} HEAD is not a SHA-1 commit")
    return commit


def _git_blob_sha1(contents: bytes) -> str:
    header = f"blob {len(contents)}\0".encode("ascii")
    return hashlib.sha1(
        header + contents,
        usedforsecurity=False,
    ).hexdigest()


def verify(
    dotfiles_repository: Path,
    source_repository: Path,
) -> None:
    dotfiles, provenance, _ = _load_dotfiles_provenance(dotfiles_repository)
    fixture_entry = _tree_entry(
        dotfiles,
        FIXTURE_PATH,
        "dotfiles fixture",
    )
    _require_clean(dotfiles, FIXTURE_PATH, "dotfiles fixture")

    source = _require_git_root(source_repository, "source")
    if _head_commit(source, "source") != provenance.source_commit:
        _fail("source HEAD does not match provenance source_commit")
    source_path = Path(*PurePosixPath(provenance.source_path).parts)
    source_entry = _tree_entry(source, source_path, "source path")
    _require_clean(source, source_path, "source path")

    if source_entry.mode != "100755":
        _fail("source path committed mode is not 100755")
    if fixture_entry.mode != "100755":
        _fail("dotfiles fixture committed mode is not 100755")

    source_bytes = _read_regular_file(
        source / source_path,
        "source path",
    )
    fixture_bytes = _read_regular_file(
        dotfiles / FIXTURE_PATH,
        "dotfiles fixture",
    )

    if (
        source_entry.object_id != provenance.git_blob_sha1
        or _git_blob_sha1(source_bytes) != provenance.git_blob_sha1
    ):
        _fail("source Git blob does not match provenance")
    if hashlib.sha256(source_bytes).hexdigest() != provenance.sha256:
        _fail("source SHA-256 does not match provenance")
    if (
        fixture_entry.object_id != provenance.git_blob_sha1
        or _git_blob_sha1(fixture_bytes) != provenance.git_blob_sha1
    ):
        _fail("dotfiles fixture Git blob does not match provenance")
    if hashlib.sha256(fixture_bytes).hexdigest() != provenance.sha256:
        _fail("dotfiles fixture SHA-256 does not match provenance")
    if source_bytes != fixture_bytes:
        _fail("source and fixture bytes do not match")


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Verify the committed profile-sync source provenance.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    source_commit = subparsers.add_parser(
        "source-commit",
        help="print the validated provenance source commit",
    )
    source_commit.add_argument(
        "--dotfiles-repository",
        type=Path,
        required=True,
    )

    verify_parser = subparsers.add_parser(
        "verify",
        help="verify dotfiles and hermes-home Git repositories",
    )
    verify_parser.add_argument(
        "--dotfiles-repository",
        type=Path,
        required=True,
    )
    verify_parser.add_argument(
        "--source-repository",
        type=Path,
        required=True,
    )
    return parser


def main(arguments: list[str] | None = None) -> int:
    parsed = _parser().parse_args(arguments)
    try:
        if parsed.command == "source-commit":
            print(read_source_commit(parsed.dotfiles_repository))
        else:
            verify(
                parsed.dotfiles_repository,
                parsed.source_repository,
            )
            print("profile sync provenance verified")
    except VerificationError as error:
        print(f"{ERROR_PREFIX}: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
